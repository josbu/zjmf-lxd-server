package handlers
import (
	"bytes"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"io"
	"lxdweb/database"
	"lxdweb/models"
	"net/http"
	"time"
	"github.com/gin-contrib/sessions"
	"github.com/gin-gonic/gin"
)
func ContainersPage(c *gin.Context) {
	session := sessions.Default(c)
	username := session.Get("username")
	c.HTML(http.StatusOK, "containers.html", gin.H{
		"title":    "容器管理 - LXD管理后台",
		"username": username,
	})
}
func GetContainers(c *gin.Context) {
	var containers []models.ContainerCache
	database.DB.Order("node_id ASC, hostname ASC").Find(&containers)
	
	allContainers := make([]map[string]interface{}, 0, len(containers))
	for _, container := range containers {
		allContainers = append(allContainers, map[string]interface{}{
			"node_id":       container.NodeID,
			"node_name":     container.NodeName,
			"hostname":      container.Hostname,
			"status":        container.Status,
			"ipv4":          container.IPv4,
			"ipv6":          container.IPv6,
			"image":         container.Image,
			"cpus":          container.CPUs,
			"memory":        container.Memory,
			"disk":          container.Disk,
			"traffic_limit": container.TrafficLimit,
			"cpu_usage":     container.CPUUsage,
			"memory_usage":  container.MemoryUsage,
			"memory_total":  container.MemoryTotal,
			"disk_usage":    container.DiskUsage,
			"disk_total":    container.DiskTotal,
			"traffic_total": container.TrafficTotal,
			"traffic_in":    container.TrafficIn,
			"traffic_out":   container.TrafficOut,
			"last_sync":     container.LastSync,
		})
	}
	
	c.JSON(http.StatusOK, gin.H{
		"code": 200,
		"msg":  "success",
		"data": allContainers,
	})
}
func GetContainerDetail(c *gin.Context) {
	name := c.Param("name")
	nodeID := c.Query("node_id")
	var node models.Node
	if err := database.DB.First(&node, nodeID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{
			"code": 404,
			"msg":  "节点不存在",
		})
		return
	}
	detail := fetchContainerDetail(node, name)
	if detail == nil {
		c.JSON(http.StatusNotFound, gin.H{
			"code": 404,
			"msg":  "容器不存在",
		})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"code": 200,
		"msg":  "success",
		"data": detail,
	})
}
func StartContainer(c *gin.Context) {
	name := c.Param("name")
	nodeID := c.Query("node_id")
	var node models.Node
	if err := database.DB.First(&node, nodeID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{
			"code": 404,
			"msg":  "节点不存在",
		})
		return
	}
	result := callNodeAPI(node, "GET", "/api/boot?hostname="+name, nil)
	c.JSON(http.StatusOK, result)
}
func StopContainer(c *gin.Context) {
	name := c.Param("name")
	nodeID := c.Query("node_id")
	var node models.Node
	if err := database.DB.First(&node, nodeID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{
			"code": 404,
			"msg":  "节点不存在",
		})
		return
	}
	result := callNodeAPI(node, "GET", "/api/stop?hostname="+name, nil)
	c.JSON(http.StatusOK, result)
}
func RestartContainer(c *gin.Context) {
	name := c.Param("name")
	nodeID := c.Query("node_id")
	var node models.Node
	if err := database.DB.First(&node, nodeID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{
			"code": 404,
			"msg":  "节点不存在",
		})
		return
	}
	result := callNodeAPI(node, "GET", "/api/reboot?hostname="+name, nil)
	c.JSON(http.StatusOK, result)
}
func DeleteContainer(c *gin.Context) {
	name := c.Param("name")
	nodeID := c.Query("node_id")
	var node models.Node
	if err := database.DB.First(&node, nodeID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{
			"code": 404,
			"msg":  "节点不存在",
		})
		return
	}
	result := callNodeAPI(node, "GET", "/api/delete?hostname="+name, nil)
	c.JSON(http.StatusOK, result)
}
func CreateContainer(c *gin.Context) {
	var req map[string]interface{}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"code": 400,
			"msg":  "参数错误",
		})
		return
	}
	nodeID := req["node_id"]
	var node models.Node
	if err := database.DB.First(&node, nodeID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{
			"code": 404,
			"msg":  "节点不存在",
		})
		return
	}
	result := callNodeAPI(node, "POST", "/api/create", req)
	c.JSON(http.StatusOK, result)
}
func fetchContainersFromNode(node models.Node) []map[string]interface{} {
	result := callNodeAPI(node, "GET", "/api/list", nil)
	if result["code"] != float64(200) {
		return []map[string]interface{}{}
	}
	data, ok := result["data"].([]interface{})
	if !ok {
		return []map[string]interface{}{}
	}
	containers := make([]map[string]interface{}, 0, len(data))
	for _, item := range data {
		if container, ok := item.(map[string]interface{}); ok {
			hostname, _ := container["hostname"].(string)
			if hostname != "" {
				detailResult := callNodeAPI(node, "GET", fmt.Sprintf("/api/info?hostname=%s", hostname), nil)
				if detailResult["code"] == float64(200) {
					if detailData, ok := detailResult["data"].(map[string]interface{}); ok {
						if cpuUsage, ok := detailData["cpu_percent"].(float64); ok {
							container["cpu_usage"] = cpuUsage
						} else if cpuUsage, ok := detailData["cpu_usage"].(float64); ok {
							container["cpu_usage"] = cpuUsage
						}
						if memUsageRaw, ok := detailData["memory_usage_raw"].(float64); ok {
							container["memory_usage"] = uint64(memUsageRaw)
						}
						if memTotal, ok := detailData["memory"].(float64); ok {
							container["memory_total"] = uint64(memTotal * 1024 * 1024) 
						}
						if diskUsageRaw, ok := detailData["disk_usage_raw"].(float64); ok {
							container["disk_usage"] = uint64(diskUsageRaw)
						}
						if diskTotal, ok := detailData["disk"].(float64); ok {
							container["disk_total"] = uint64(diskTotal * 1024 * 1024) 
						}
						if trafficRaw, ok := detailData["traffic_usage_raw"].(float64); ok {
							container["traffic_total"] = uint64(trafficRaw)
							container["traffic_in"] = uint64(trafficRaw * 0.5)
							container["traffic_out"] = uint64(trafficRaw * 0.5)
						}
					}
				}
			}
			containers = append(containers, container)
		}
	}
	return containers
}
func fetchContainerDetail(node models.Node, name string) map[string]interface{} {
	result := callNodeAPI(node, "GET", fmt.Sprintf("/api/info?hostname=%s", name), nil)
	if result["code"] == float64(200) {
		if data, ok := result["data"].(map[string]interface{}); ok {
			return data
		}
	}
	return nil
}
func callNodeAPI(node models.Node, method, path string, data interface{}) map[string]interface{} {
	client := &http.Client{
		Timeout: 30 * time.Second,
		Transport: &http.Transport{
			TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
		},
	}
	var body io.Reader
	if data != nil {
		jsonData, _ := json.Marshal(data)
		body = bytes.NewBuffer(jsonData)
	}
	req, err := http.NewRequest(method, node.Address+path, body)
	if err != nil {
		return map[string]interface{}{
			"code": 500,
			"msg":  "请求创建失败: " + err.Error(),
		}
	}
	if node.APIKey != "" {
		req.Header.Set("apikey", node.APIKey)
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := client.Do(req)
	if err != nil {
		return map[string]interface{}{
			"code": 500,
			"msg":  "请求失败: " + err.Error(),
		}
	}
	defer resp.Body.Close()
	var result map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return map[string]interface{}{
			"code": 500,
			"msg":  "响应解析失败: " + err.Error(),
		}
	}
	return result
}
