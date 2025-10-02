package handlers

import (
	"net/http"
	"strconv"

	"lxdweb/database"
	"lxdweb/models"
	"lxdweb/services"

	"github.com/gin-contrib/sessions"
	"github.com/gin-gonic/gin"
)

func SyncAllNodes(c *gin.Context) {
	session := sessions.Default(c)
	username := session.Get("username")
	if username == nil {
		c.JSON(http.StatusUnauthorized, gin.H{
			"code": 401,
			"msg":  "未登录",
		})
		return
	}

	go services.SyncAllNodesAsync()

	c.JSON(http.StatusOK, gin.H{
		"code": 200,
		"msg":  "同步任务已启动，请稍后刷新页面查看结果",
	})
}

func SyncNode(c *gin.Context) {
	session := sessions.Default(c)
	username := session.Get("username")
	if username == nil {
		c.JSON(http.StatusUnauthorized, gin.H{
			"code": 401,
			"msg":  "未登录",
		})
		return
	}

	nodeIDStr := c.Param("id")
	nodeID, err := strconv.ParseUint(nodeIDStr, 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"code": 400,
			"msg":  "节点ID格式错误",
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

	if services.IsSyncing(uint(nodeID)) {
		c.JSON(http.StatusOK, gin.H{
			"code": 400,
			"msg":  "该节点正在同步中，请稍后再试",
		})
		return
	}

	go services.SyncNodeContainers(uint(nodeID), true)

	c.JSON(http.StatusOK, gin.H{
		"code": 200,
		"msg":  "同步任务已启动，请稍后刷新页面查看结果",
	})
}

func GetSyncTasks(c *gin.Context) {
	session := sessions.Default(c)
	username := session.Get("username")
	if username == nil {
		c.JSON(http.StatusUnauthorized, gin.H{
			"code": 401,
			"msg":  "未登录",
		})
		return
	}

	var tasks []models.SyncTask
	database.DB.Order("created_at DESC").Limit(50).Find(&tasks)

	c.JSON(http.StatusOK, gin.H{
		"code": 200,
		"msg":  "success",
		"data": tasks,
	})
}

func GetSyncStatus(c *gin.Context) {
	session := sessions.Default(c)
	username := session.Get("username")
	if username == nil {
		c.JSON(http.StatusUnauthorized, gin.H{
			"code": 401,
			"msg":  "未登录",
		})
		return
	}

	nodeIDStr := c.Query("node_id")
	
	var status []map[string]interface{}
	
	if nodeIDStr != "" {
		nodeID, err := strconv.ParseUint(nodeIDStr, 10, 32)
		if err == nil {
			isSyncing := services.IsSyncing(uint(nodeID))
			
			var lastTask models.SyncTask
			database.DB.Where("node_id = ?", nodeID).Order("created_at DESC").First(&lastTask)
			
			status = append(status, map[string]interface{}{
				"node_id":   uint(nodeID),
				"syncing":   isSyncing,
				"last_task": lastTask,
			})
		}
	} else {
		var nodes []models.Node
		database.DB.Find(&nodes)
		
		for _, node := range nodes {
			isSyncing := services.IsSyncing(node.ID)
			
			var lastTask models.SyncTask
			database.DB.Where("node_id = ?", node.ID).Order("created_at DESC").First(&lastTask)
			
			status = append(status, map[string]interface{}{
				"node_id":   node.ID,
				"node_name": node.Name,
				"syncing":   isSyncing,
				"last_task": lastTask,
			})
		}
	}

	c.JSON(http.StatusOK, gin.H{
		"code": 200,
		"msg":  "success",
		"data": status,
	})
}

