package handlers
import (
	"crypto/tls"
	"encoding/json"
	"fmt"
	"lxdweb/database"
	"lxdweb/models"
	"lxdweb/services"
	"net/http"
	"strconv"
	"time"
	"github.com/gin-contrib/sessions"
	"github.com/gin-gonic/gin"
)

func applySyncPreset(preset string) (batchSize int, batchInterval int) {
	switch preset {
	case "low":
		return 3, 10
	case "medium":
		return 5, 5
	case "high":
		return 10, 3
	case "custom":
		return 0, 0
	default:
		return 5, 5
	}
}

// NodesPage 节点管理页面
// @Summary 节点管理页面
// @Description 显示节点管理页面
// @Tags 节点管理
// @Produce html
// @Success 200 {string} string "HTML页面"
// @Router /nodes [get]
func NodesPage(c *gin.Context) {
	session := sessions.Default(c)
	username := session.Get("username")
	c.HTML(http.StatusOK, "nodes.html", gin.H{
		"title":    "节点管理 - LXD管理后台",
		"username": username,
	})
}

// NodeDetailPage 节点详情页面
// @Summary 节点详情页面
// @Description 显示单个节点的详细信息和管理界面
// @Tags 节点管理
// @Produce html
// @Param id path string true "节点ID"
// @Success 200 {string} string "HTML页面"
// @Router /nodes/{id} [get]
func NodeDetailPage(c *gin.Context) {
	session := sessions.Default(c)
	username := session.Get("username")
	nodeID := c.Param("id")
	
	c.HTML(http.StatusOK, "node_detail.html", gin.H{
		"title":    "节点详情 - LXD管理后台",
		"username": username,
		"node_id":  nodeID,
	})
}

// NodeContainersPage 节点容器列表页面
func NodeContainersPage(c *gin.Context) {
	session := sessions.Default(c)
	username := session.Get("username")
	nodeID := c.Param("id")
	
	c.HTML(http.StatusOK, "node_containers.html", gin.H{
		"title":    "容器列表 - LXD管理后台",
		"username": username,
		"node_id":  nodeID,
	})
}

// ContainerDetailPage 容器详情页面
func ContainerDetailPage(c *gin.Context) {
	session := sessions.Default(c)
	username := session.Get("username")
	nodeID := c.Param("id")
	containerName := c.Param("name")
	
	c.HTML(http.StatusOK, "container_detail.html", gin.H{
		"title":          "容器详情 - LXD管理后台",
		"username":       username,
		"node_id":        nodeID,
		"container_name": containerName,
	})
}

// NodeNATPage 节点NAT列表页面
func NodeNATPage(c *gin.Context) {
	session := sessions.Default(c)
	username := session.Get("username")
	nodeID := c.Param("id")
	
	c.HTML(http.StatusOK, "node_nat.html", gin.H{
		"title":    "NAT规则 - LXD管理后台",
		"username": username,
		"node_id":  nodeID,
	})
}

// NodeIPv6Page 节点IPv6列表页面
func NodeIPv6Page(c *gin.Context) {
	session := sessions.Default(c)
	username := session.Get("username")
	nodeID := c.Param("id")
	
	c.HTML(http.StatusOK, "node_ipv6.html", gin.H{
		"title":    "IPv6绑定 - LXD管理后台",
		"username": username,
		"node_id":  nodeID,
	})
}

// NodeProxyPage 节点代理列表页面
func NodeProxyPage(c *gin.Context) {
	session := sessions.Default(c)
	username := session.Get("username")
	nodeID := c.Param("id")
	
	c.HTML(http.StatusOK, "node_proxy.html", gin.H{
		"title":    "反向代理 - LXD管理后台",
		"username": username,
		"node_id":  nodeID,
	})
}
// GetNodes 获取节点列表
// @Summary 获取节点列表
// @Description 查询所有LXD节点及其系统信息，支持按状态过滤
// @Tags 节点管理
// @Produce json
// @Param status query string false "节点状态(active/inactive)"
// @Success 200 {object} map[string]interface{} "成功返回节点列表"
// @Failure 500 {object} map[string]interface{} "查询失败"
// @Router /api/nodes [get]
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
// GetNode 获取单个节点
// @Summary 获取单个节点
// @Description 根据ID获取节点详情
// @Tags 节点管理
// @Produce json
// @Param id path string true "节点ID"
// @Success 200 {object} map[string]interface{} "成功返回节点信息"
// @Failure 404 {object} map[string]interface{} "节点不存在"
// @Router /api/nodes/{id} [get]
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
// CreateNode 创建节点
// @Summary 创建节点
// @Description 添加新的LXD节点到管理系统
// @Tags 节点管理
// @Accept json
// @Produce json
// @Param body body models.CreateNodeRequest true "节点配置参数"
// @Success 200 {object} map[string]interface{} "创建成功"
// @Failure 400 {object} map[string]interface{} "参数错误"
// @Router /api/nodes [post]
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
	syncPreset := req.SyncPreset
	if syncPreset == "" {
		syncPreset = "medium"
	}
	
	batchSize := req.BatchSize
	batchInterval := req.BatchInterval
	
	if syncPreset != "custom" {
		batchSize, batchInterval = applySyncPreset(syncPreset)
	}
	
	if batchSize <= 0 {
		batchSize = 5
	}
	if batchInterval <= 0 {
		batchInterval = 5
	}
	
	node := models.Node{
		Name:          req.Name,
		Description:   req.Description,
		Address:       req.Address,
		APIKey:        req.APIKey,
		Status:        "inactive",
		SyncPreset:    syncPreset,
		BatchSize:     batchSize,
		BatchInterval: batchInterval,
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
// UpdateNode 更新节点
// @Summary 更新节点
// @Description 更新节点配置信息
// @Tags 节点管理
// @Accept json
// @Produce json
// @Param id path string true "节点ID"
// @Param body body models.UpdateNodeRequest true "更新参数"
// @Success 200 {object} map[string]interface{} "更新成功"
// @Failure 400 {object} map[string]interface{} "参数错误"
// @Failure 404 {object} map[string]interface{} "节点不存在"
// @Router /api/nodes/{id} [put]
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
	
	if req.SyncPreset != "" {
		updates["sync_preset"] = req.SyncPreset
		
		if req.SyncPreset != "custom" {
			batchSize, batchInterval := applySyncPreset(req.SyncPreset)
			updates["batch_size"] = batchSize
			updates["batch_interval"] = batchInterval
		}
	}
	
	if req.SyncPreset == "custom" {
		if req.BatchSize > 0 {
			updates["batch_size"] = req.BatchSize
		}
		if req.BatchInterval > 0 {
			updates["batch_interval"] = req.BatchInterval
		}
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
// DeleteNode 删除节点
// @Summary 删除节点
// @Description 从管理系统中删除指定节点及其所有关联数据
// @Tags 节点管理
// @Produce json
// @Param id path string true "节点ID"
// @Success 200 {object} map[string]interface{} "删除成功"
// @Failure 500 {object} map[string]interface{} "删除失败"
// @Router /api/nodes/{id} [delete]
func DeleteNode(c *gin.Context) {
	id := c.Param("id")
	nodeID, err := strconv.ParseUint(id, 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"code": 400,
			"msg":  "无效的节点ID",
		})
		return
	}
	
	database.DB.Where("node_id = ?", nodeID).Delete(&models.ContainerCache{})
	database.DB.Where("node_id = ?", nodeID).Delete(&models.NATRule{})
	database.DB.Where("node_id = ?", nodeID).Delete(&models.IPv6BindingCache{})
	database.DB.Where("node_id = ?", nodeID).Delete(&models.ProxyConfigCache{})
	database.DB.Where("node_id = ?", nodeID).Delete(&models.NodeInfoCache{})
	
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
// TestNode 测试节点连接
// @Summary 测试节点连接
// @Description 测试与LXD节点的连接状态
// @Tags 节点管理
// @Produce json
// @Param id path string true "节点ID"
// @Success 200 {object} map[string]interface{} "测试成功"
// @Failure 404 {object} map[string]interface{} "节点不存在"
// @Failure 500 {object} map[string]interface{} "连接失败"
// @Router /api/nodes/{id}/test [post]
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
		go services.RefreshNodeCache(uint(idInt))
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
// RefreshNodeCache 刷新节点缓存
// @Summary 刷新节点缓存
// @Description 刷新指定节点的系统信息缓存
// @Tags 节点管理
// @Produce json
// @Param id path string true "节点ID"
// @Success 200 {object} map[string]interface{} "刷新成功"
// @Failure 404 {object} map[string]interface{} "节点不存在"
// @Router /api/nodes/{id}/refresh [post]
func RefreshNodeCache(c *gin.Context) {
	id := c.Param("id")
	idInt, _ := strconv.ParseUint(id, 10, 32)
	
	// 更新节点系统信息缓存
	if err := services.RefreshNodeCache(uint(idInt)); err != nil {
		c.JSON(http.StatusNotFound, gin.H{
			"code": 404,
			"msg":  "节点不存在",
		})
		return
	}
	
	// 刷新容器缓存（从lxdapi缓存快速复制）
	go services.RefreshNodeContainers(uint(idInt), true)
	
	c.JSON(http.StatusOK, gin.H{
		"code": 200,
		"msg":  "刷新任务已启动",
	})
}

func updateNodeStatus(nodeID uint, status string) {
	now := time.Now()
	database.DB.Model(&models.Node{}).Where("id = ?", nodeID).Updates(map[string]interface{}{
		"status":     status,
		"last_check": now,
	})
}
