package services

import (
	"bytes"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"sync"
	"time"

	"lxdweb/config"
	"lxdweb/database"
	"lxdweb/models"
	"gorm.io/gorm/clause"
)

var (
	syncMutex    sync.Mutex
	syncRunning  = make(map[uint]bool) 
)

func StartContainerSyncService() {
	syncInterval := getSyncInterval()
	log.Printf("✓ 容器同步服务启动，同步间隔: %d秒", syncInterval)

	time.Sleep(10 * time.Second)
	SyncAllNodesAsync()

	ticker := time.NewTicker(time.Duration(syncInterval) * time.Second)
	go func() {
		for range ticker.C {
			SyncAllNodesAsync()
		}
	}()
}

func SyncAllNodesAsync() {
	var nodes []models.Node
	database.DB.Where("status = ?", "active").Find(&nodes)
	
	log.Printf("[SYNC] 开始同步 %d 个活动节点", len(nodes))
	
	for _, node := range nodes {
		go SyncNodeContainers(node.ID, false)
	}
}

func SyncNodeContainers(nodeID uint, manual bool) error {
	syncMutex.Lock()
	if syncRunning[nodeID] {
		syncMutex.Unlock()
		return fmt.Errorf("节点 %d 正在同步中", nodeID)
	}
	syncRunning[nodeID] = true
	syncMutex.Unlock()
	
	defer func() {
		syncMutex.Lock()
		syncRunning[nodeID] = false
		syncMutex.Unlock()
	}()
	
	var node models.Node
	if err := database.DB.First(&node, nodeID).Error; err != nil {
		return fmt.Errorf("节点不存在: %v", err)
	}

	now := time.Now()
	task := models.SyncTask{
		NodeID:     node.ID,
		NodeName:   node.Name,
		Status:     "running",
		StartTime:  &now,
	}
	database.DB.Create(&task)
	
	log.Printf("[SYNC] 开始同步节点 %s (ID: %d)%s", node.Name, node.ID, map[bool]string{true: " [手动]", false: ""}[manual])

	listResult := callNodeAPI(node, "GET", "/api/list", nil)
	if listResult["code"] != float64(200) {
		task.Status = "failed"
		task.ErrorMessage = fmt.Sprintf("获取容器列表失败: %v", listResult["msg"])
		endTime := time.Now()
		task.EndTime = &endTime
		database.DB.Save(&task)

		log.Printf("[SYNC] 节点 %s 连接失败，清理旧缓存数据", node.Name)
		database.DB.Unscoped().Where("node_id = ?", node.ID).Delete(&models.ContainerCache{})
		
		return fmt.Errorf("获取容器列表失败")
	}
	
	data, ok := listResult["data"].([]interface{})
	if !ok {
		task.Status = "failed"
		task.ErrorMessage = "容器列表格式错误"
		endTime := time.Now()
		task.EndTime = &endTime
		database.DB.Save(&task)

		log.Printf("[SYNC] 节点 %s 返回数据格式错误，清理旧缓存数据", node.Name)
		database.DB.Unscoped().Where("node_id = ?", node.ID).Delete(&models.ContainerCache{})
		
		return fmt.Errorf("容器列表格式错误")
	}
	
	task.TotalCount = len(data)
	database.DB.Save(&task)

	successCount := 0
	failedCount := 0

	batchSize := getBatchSize()
	batchInterval := getBatchInterval()
	
	log.Printf("[SYNC] 节点 %s 开始分批同步，批量大小: %d, 间隔: %ds", node.Name, batchSize, batchInterval)

	for i := 0; i < len(data); i += batchSize {
		end := i + batchSize
		if end > len(data) {
			end = len(data)
		}
		
		batch := data[i:end]
		batchNum := (i / batchSize) + 1
		totalBatches := (len(data) + batchSize - 1) / batchSize
		
		log.Printf("[SYNC] 节点 %s 处理第 %d/%d 批 (容器 %d-%d/%d)",
			node.Name, batchNum, totalBatches, i+1, end, len(data))

		var wg sync.WaitGroup
		resultChan := make(chan map[string]interface{}, len(batch))
		
		for _, item := range batch {
			container, ok := item.(map[string]interface{})
			if !ok {
				continue
			}
			
			hostname, _ := container["hostname"].(string)
			if hostname == "" {
				continue
			}
			
			wg.Add(1)
			go func(hostname string, baseInfo map[string]interface{}) {
				defer wg.Done()
				
				detailResult := callNodeAPI(node, "GET", fmt.Sprintf("/api/info?hostname=%s", hostname), nil)
				if detailResult["code"] == float64(200) {
					if detailData, ok := detailResult["data"].(map[string]interface{}); ok {
						for k, v := range baseInfo {
							if _, exists := detailData[k]; !exists {
								detailData[k] = v
							}
						}
						detailData["hostname"] = hostname
						resultChan <- detailData
					}
				} else {
					baseInfo["hostname"] = hostname
					resultChan <- baseInfo
				}
			}(hostname, container)
		}
		
		go func() {
			wg.Wait()
			close(resultChan)
		}()

		for containerData := range resultChan {
			if err := updateContainerCache(node, containerData); err != nil {
				log.Printf("[SYNC] 更新容器缓存失败: %v", err)
				failedCount++
			} else {
				successCount++
			}
		}
		
		if end < len(data) {
			time.Sleep(time.Duration(batchInterval) * time.Second)
		}
	}

	var cachedContainers []models.ContainerCache
	database.DB.Where("node_id = ?", node.ID).Find(&cachedContainers)
	
	existingHostnames := make(map[string]bool)
	for _, item := range data {
		if container, ok := item.(map[string]interface{}); ok {
			if hostname, ok := container["hostname"].(string); ok {
				existingHostnames[hostname] = true
			}
		}
	}
	
	for _, cached := range cachedContainers {
		if !existingHostnames[cached.Hostname] {
			database.DB.Unscoped().Delete(&cached)
			log.Printf("[SYNC] 删除不存在的容器缓存: %s", cached.Hostname)
		}
	}

	task.Status = "completed"
	task.SuccessCount = successCount
	task.FailedCount = failedCount
	endTime := time.Now()
	task.EndTime = &endTime
	database.DB.Save(&task)
	
	log.Printf("[SYNC] 节点 %s 同步完成: 成功 %d, 失败 %d, 总计 %d", 
		node.Name, successCount, failedCount, task.TotalCount)
	
	return nil
}

func updateContainerCache(node models.Node, data map[string]interface{}) error {
	hostname, _ := data["hostname"].(string)
	if hostname == "" {
		return fmt.Errorf("hostname为空")
	}

	updates := map[string]interface{}{
		"node_name": node.Name,
		"last_sync": time.Now(),
		"sync_error": "",
	}

	if status, ok := data["status"].(string); ok {
		updates["status"] = status
	}
	if ipv4, ok := data["ipv4"].(string); ok {
		updates["ipv4"] = ipv4
	}
	if ipv6, ok := data["ipv6"].(string); ok {
		updates["ipv6"] = ipv6
	}
	if image, ok := data["image"].(string); ok {
		updates["image"] = image
	}
	if cpus, ok := data["cpus"].(float64); ok {
		updates["cpus"] = int(cpus)
	}

	var memory, disk string
	var trafficLimit int
	if config, ok := data["config"].(map[string]interface{}); ok {
		if mem, ok := config["memory"].(string); ok {
			memory = mem
		}
		if dsk, ok := config["disk"].(string); ok {
			disk = dsk
		}
		if limit, ok := config["traffic_limit"].(float64); ok {
			trafficLimit = int(limit)
		}
	}

	if memory == "" {
		if mem, ok := data["memory"].(float64); ok {
			memory = fmt.Sprintf("%.0fMB", mem)
		}
	}
	if disk == "" {
		if dsk, ok := data["disk"].(float64); ok {
			disk = fmt.Sprintf("%.0fMB", dsk)
		}
	}
	
	if memory != "" {
		updates["memory"] = memory
	}
	if disk != "" {
		updates["disk"] = disk
	}
	if trafficLimit > 0 {
		updates["traffic_limit"] = trafficLimit
	}

	if cpuUsage, ok := data["cpu_percent"].(float64); ok {
		updates["cpu_usage"] = cpuUsage
	} else if cpuUsage, ok := data["cpu_usage"].(float64); ok {
		updates["cpu_usage"] = cpuUsage
	}

	if memUsageRaw, ok := data["memory_usage_raw"].(float64); ok {
		updates["memory_usage"] = uint64(memUsageRaw)
	}
	if memTotal, ok := data["memory"].(float64); ok {
		updates["memory_total"] = uint64(memTotal * 1024 * 1024) 
	}

	if diskUsageRaw, ok := data["disk_usage_raw"].(float64); ok {
		updates["disk_usage"] = uint64(diskUsageRaw)
	}
	if diskTotal, ok := data["disk"].(float64); ok {
		updates["disk_total"] = uint64(diskTotal * 1024 * 1024) 
	}

	if trafficRaw, ok := data["traffic_usage_raw"].(float64); ok {
		updates["traffic_total"] = uint64(trafficRaw)
		updates["traffic_in"] = uint64(trafficRaw * 0.5)
		updates["traffic_out"] = uint64(trafficRaw * 0.5)
	}

	cache := models.ContainerCache{
		NodeID:   node.ID,
		NodeName: node.Name,
		Hostname: hostname,
	}

	if status, ok := updates["status"].(string); ok {
		cache.Status = status
	}
	if ipv4, ok := updates["ipv4"].(string); ok {
		cache.IPv4 = ipv4
	}
	if ipv6, ok := updates["ipv6"].(string); ok {
		cache.IPv6 = ipv6
	}
	if image, ok := updates["image"].(string); ok {
		cache.Image = image
	}
	if cpus, ok := updates["cpus"].(int); ok {
		cache.CPUs = cpus
	}
	if memory, ok := updates["memory"].(string); ok {
		cache.Memory = memory
	}
	if disk, ok := updates["disk"].(string); ok {
		cache.Disk = disk
	}
	if trafficLimit, ok := updates["traffic_limit"].(int); ok {
		cache.TrafficLimit = trafficLimit
	}
	if cpuUsage, ok := updates["cpu_usage"].(float64); ok {
		cache.CPUUsage = cpuUsage
	}
	if memUsage, ok := updates["memory_usage"].(uint64); ok {
		cache.MemoryUsage = memUsage
	}
	if memTotal, ok := updates["memory_total"].(uint64); ok {
		cache.MemoryTotal = memTotal
	}
	if diskUsage, ok := updates["disk_usage"].(uint64); ok {
		cache.DiskUsage = diskUsage
	}
	if diskTotal, ok := updates["disk_total"].(uint64); ok {
		cache.DiskTotal = diskTotal
	}
	if trafficTotal, ok := updates["traffic_total"].(uint64); ok {
		cache.TrafficTotal = trafficTotal
	}
	if trafficIn, ok := updates["traffic_in"].(uint64); ok {
		cache.TrafficIn = trafficIn
	}
	if trafficOut, ok := updates["traffic_out"].(uint64); ok {
		cache.TrafficOut = trafficOut
	}
	if lastSync, ok := updates["last_sync"].(time.Time); ok {
		cache.LastSync = lastSync
	}
	if syncError, ok := updates["sync_error"].(string); ok {
		cache.SyncError = syncError
	}

	result := database.DB.Clauses(clause.OnConflict{
		Columns: []clause.Column{{Name: "node_id"}, {Name: "hostname"}},
		DoUpdates: clause.AssignmentColumns([]string{
			"node_name", "status", "ipv4", "ipv6", "image",
			"cpus", "memory", "disk", "traffic_limit",
			"cpu_usage", "memory_usage", "memory_total",
			"disk_usage", "disk_total",
			"traffic_total", "traffic_in", "traffic_out",
			"last_sync", "sync_error",
		}),
	}).Create(&cache)
	
	return result.Error
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

func IsSyncing(nodeID uint) bool {
	syncMutex.Lock()
	defer syncMutex.Unlock()
	return syncRunning[nodeID]
}

func getBatchSize() int {
	if config.AppConfig != nil && config.AppConfig.Sync.BatchSize > 0 {
		return config.AppConfig.Sync.BatchSize
	}
	return 5 
}

func getBatchInterval() int {
	if config.AppConfig != nil && config.AppConfig.Sync.BatchInterval > 0 {
		return config.AppConfig.Sync.BatchInterval
	}
	return 2 
}

func getSyncInterval() int {
	if config.AppConfig != nil && config.AppConfig.Sync.Interval > 0 {
		return config.AppConfig.Sync.Interval
	}
	return 300 
}

