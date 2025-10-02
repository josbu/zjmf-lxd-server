package handlers
import (
	"lxdweb/database"
	"lxdweb/models"
	"net/http"
	"github.com/gin-contrib/sessions"
	"github.com/gin-gonic/gin"
)
func NATPage(c *gin.Context) {
	session := sessions.Default(c)
	username := session.Get("username")
	c.HTML(http.StatusOK, "nat.html", gin.H{
		"title":    "NAT规则管理 - LXD管理后台",
		"username": username,
	})
}
func GetNATRules(c *gin.Context) {
	var rules []models.NATRule
	query := database.DB.Preload("Node")
	if nodeID := c.Query("node_id"); nodeID != "" {
		query = query.Where("node_id = ?", nodeID)
	}
	if err := query.Find(&rules).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"code": 500,
			"msg":  "查询失败: " + err.Error(),
		})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"code": 200,
		"msg":  "success",
		"data": rules,
	})
}
func GetNATRule(c *gin.Context) {
	id := c.Param("id")
	var rule models.NATRule
	if err := database.DB.Preload("Node").First(&rule, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{
			"code": 404,
			"msg":  "NAT规则不存在",
		})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"code": 200,
		"msg":  "success",
		"data": rule,
	})
}
func CreateNATRule(c *gin.Context) {
	var req models.CreateNATRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"code": 400,
			"msg":  "参数错误: " + err.Error(),
		})
		return
	}
	var node models.Node
	if err := database.DB.First(&node, req.NodeID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{
			"code": 404,
			"msg":  "节点不存在",
		})
		return
	}
	var existingRule models.NATRule
	if err := database.DB.Where("node_id = ? AND external_port = ? AND protocol = ?", 
		req.NodeID, req.ExternalPort, req.Protocol).First(&existingRule).Error; err == nil {
		c.JSON(http.StatusConflict, gin.H{
			"code": 409,
			"msg":  "该端口已被占用",
		})
		return
	}
	natData := map[string]interface{}{
		"hostname": req.ContainerHostname,
		"external": req.ExternalPort,
		"internal": req.InternalPort,
		"protocol": req.Protocol,
	}
	result := callNodeAPI(node, "POST", "/api/nat/add", natData)
	if result["code"] != float64(200) {
		c.JSON(http.StatusInternalServerError, gin.H{
			"code": 500,
			"msg":  result["msg"],
		})
		return
	}
	rule := models.NATRule{
		NodeID:            req.NodeID,
		ContainerHostname: req.ContainerHostname,
		ExternalPort:      req.ExternalPort,
		InternalPort:      req.InternalPort,
		Protocol:          req.Protocol,
		Description:       req.Description,
		Status:            "active",
	}
	if err := database.DB.Create(&rule).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"code": 500,
			"msg":  "保存失败: " + err.Error(),
		})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"code": 200,
		"msg":  "NAT规则创建成功",
		"data": rule,
	})
}
func UpdateNATRule(c *gin.Context) {
	id := c.Param("id")
	var rule models.NATRule
	if err := database.DB.First(&rule, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{
			"code": 404,
			"msg":  "NAT规则不存在",
		})
		return
	}
	var req models.UpdateNATRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"code": 400,
			"msg":  "参数错误: " + err.Error(),
		})
		return
	}
	if req.Description != "" {
		rule.Description = req.Description
	}
	if req.Status != "" {
		rule.Status = req.Status
	}
	if err := database.DB.Save(&rule).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"code": 500,
			"msg":  "更新失败: " + err.Error(),
		})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"code": 200,
		"msg":  "更新成功",
		"data": rule,
	})
}
func DeleteNATRule(c *gin.Context) {
	id := c.Param("id")
	var rule models.NATRule
	if err := database.DB.First(&rule, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{
			"code": 404,
			"msg":  "NAT规则不存在",
		})
		return
	}
	var node models.Node
	if err := database.DB.First(&node, rule.NodeID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{
			"code": 404,
			"msg":  "节点不存在",
		})
		return
	}
	natData := map[string]interface{}{
		"hostname": rule.ContainerHostname,
		"external": rule.ExternalPort,
		"protocol": rule.Protocol,
	}
	result := callNodeAPI(node, "POST", "/api/nat/delete", natData)
	if result["code"] != float64(200) {
		c.JSON(http.StatusInternalServerError, gin.H{
			"code": 500,
			"msg":  result["msg"],
		})
		return
	}
	if err := database.DB.Delete(&rule).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"code": 500,
			"msg":  "删除失败: " + err.Error(),
		})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"code": 200,
		"msg":  "删除成功",
	})
}
func SyncNATRules(c *gin.Context) {
	nodeID := c.Query("node_id")
	if nodeID == "" {
		c.JSON(http.StatusBadRequest, gin.H{
			"code": 400,
			"msg":  "缺少node_id参数",
		})
		return
	}
	var node models.Node
	if err := database.DB.First(&node, nodeID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{
			"code": 404,
			"msg":  "节点不存在",
		})
		return
	}
	result := callNodeAPI(node, "GET", "/api/nat/list", nil)
	if result["code"] != float64(200) {
		c.JSON(http.StatusInternalServerError, gin.H{
			"code": 500,
			"msg":  "同步失败: " + result["msg"].(string),
		})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"code": 200,
		"msg":  "同步成功",
		"data": result["data"],
	})
}
