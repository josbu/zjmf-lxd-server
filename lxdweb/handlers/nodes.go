package handlers
import (
	"crypto/tls"
	"encoding/json"
	"fmt"
	"lxdweb/database"
	"lxdweb/models"
	"net/http"
	"strconv"
	"time"
	"github.com/gin-contrib/sessions"
	"github.com/gin-gonic/gin"
)
func NodesPage(c *gin.Context) {
	session := sessions.Default(c)
	username := session.Get("username")
	c.HTML(http.StatusOK, "nodes.html", gin.H{
		"title":    "节点管理 - LXD管理后台",
		"username": username,
	})
}
func GetNodes(c *gin.Context) {
	var nodes []models.Node
	if err := database.DB.Order("created_at desc").Find(&nodes).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"code": 500,
			"msg":  "查询失败",
		})
		return
	}

	var caches []models.NodeInfoCache
	database.DB.Find(&caches)
	cacheMap := make(map[uint]models.NodeInfoCache)
	for _, cache := range caches {
		cacheMap[cache.NodeID] = cache
	}
	
	result := make([]map[string]interface{}, 0, len(nodes))
	for _, node := range nodes {
		nodeData := map[string]interface{}{
			"id":          node.ID,
			"name":        node.Name,
			"description": node.Description,
			"address":     node.Address,
			"api_key":     node.APIKey,
			"status":      node.Status,
			"last_check":  node.LastCheck,
			"created_at":  node.CreatedAt,
			"updated_at":  node.UpdatedAt,
		}

		if cache, ok := cacheMap[node.ID]; ok {
			var sysInfo map[string]interface{}
			if err := json.Unmarshal([]byte(cache.SystemInfo), &sysInfo); err == nil {
				nodeData["system_info"] = sysInfo
			}
		}
		
		result = append(result, nodeData)
	}
	
	c.JSON(http.StatusOK, gin.H{
		"code": 200,
		"msg":  "success",
		"data": result,
	})
}
func getNodeSystemInfo(node models.Node) map[string]interface{} {
	client := &http.Client{
		Timeout: 5 * time.Second,
		Transport: &http.Transport{
			TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
		},
	}
	req, err := http.NewRequest("GET", node.Address+"/", nil)
	if err != nil {
		return nil
	}
	if node.APIKey != "" {
		req.Header.Set("apikey", node.APIKey)
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil
	}
	defer resp.Body.Close()
	var result map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil
	}
	return result
}
func GetNode(c *gin.Context) {
	id := c.Param("id")
	var node models.Node
	if err := database.DB.First(&node, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{
			"code": 404,
			"msg":  "节点不存在",
		})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"code": 200,
		"msg":  "success",
		"data": node,
	})
}
func CreateNode(c *gin.Context) {
	var req models.CreateNodeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"code": 400,
			"msg":  "参数错误: " + err.Error(),
		})
		return
	}
	var count int64
	database.DB.Model(&models.Node{}).Where("name = ?", req.Name).Count(&count)
	if count > 0 {
		c.JSON(http.StatusBadRequest, gin.H{
			"code": 400,
			"msg":  "节点名称已存在",
		})
		return
	}
	node := models.Node{
		Name:        req.Name,
		Description: req.Description,
		Address:     req.Address,
		APIKey:      req.APIKey,
		Status:      "inactive",
	}
	if err := database.DB.Create(&node).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"code": 500,
			"msg":  "创建失败: " + err.Error(),
		})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"code": 200,
		"msg":  "创建成功",
		"data": node,
	})
}
func UpdateNode(c *gin.Context) {
	id := c.Param("id")
	var node models.Node
	if err := database.DB.First(&node, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{
			"code": 404,
			"msg":  "节点不存在",
		})
		return
	}
	var req models.UpdateNodeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"code": 400,
			"msg":  "参数错误: " + err.Error(),
		})
		return
	}
	updates := map[string]interface{}{}
	if req.Name != "" {
		var count int64
		database.DB.Model(&models.Node{}).Where("name = ? AND id != ?", req.Name, id).Count(&count)
		if count > 0 {
			c.JSON(http.StatusBadRequest, gin.H{
				"code": 400,
				"msg":  "节点名称已存在",
			})
			return
		}
		updates["name"] = req.Name
	}
	if req.Description != "" {
		updates["description"] = req.Description
	}
	if req.Address != "" {
		updates["address"] = req.Address
	}
	if req.APIKey != "" {
		updates["api_key"] = req.APIKey
	}
	if err := database.DB.Model(&node).Updates(updates).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"code": 500,
			"msg":  "更新失败: " + err.Error(),
		})
		return
	}
	database.DB.First(&node, id)
	c.JSON(http.StatusOK, gin.H{
		"code": 200,
		"msg":  "更新成功",
		"data": node,
	})
}
func DeleteNode(c *gin.Context) {
	id := c.Param("id")
	if err := database.DB.Delete(&models.Node{}, id).Error; err != nil {
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
func TestNode(c *gin.Context) {
	id := c.Param("id")
	idInt, _ := strconv.ParseUint(id, 10, 32)
	var node models.Node
	if err := database.DB.First(&node, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{
			"code": 404,
			"msg":  "节点不存在",
		})
		return
	}
	client := &http.Client{
		Timeout: 10 * time.Second,
		Transport: &http.Transport{
			TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
		},
	}
	req, err := http.NewRequest("GET", node.Address+"/api/check", nil)
	if err != nil {
		updateNodeStatus(uint(idInt), "error")
		c.JSON(http.StatusOK, gin.H{
			"code": 500,
			"msg":  "连接失败: " + err.Error(),
		})
		return
	}
	if node.APIKey != "" {
		req.Header.Set("apikey", node.APIKey)
	}
	resp, err := client.Do(req)
	if err != nil {
		updateNodeStatus(uint(idInt), "error")
		c.JSON(http.StatusOK, gin.H{
			"code": 500,
			"msg":  "连接失败: " + err.Error(),
		})
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode == 200 {
		updateNodeStatus(uint(idInt), "active")
		c.JSON(http.StatusOK, gin.H{
			"code": 200,
			"msg":  "连接成功",
		})
	} else {
		updateNodeStatus(uint(idInt), "error")
		c.JSON(http.StatusOK, gin.H{
			"code": 500,
			"msg":  fmt.Sprintf("连接失败: HTTP %d", resp.StatusCode),
		})
	}
}
func updateNodeStatus(nodeID uint, status string) {
	now := time.Now()
	database.DB.Model(&models.Node{}).Where("id = ?", nodeID).Updates(map[string]interface{}{
		"status":     status,
		"last_check": now,
	})
}
