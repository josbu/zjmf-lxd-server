package models

import (
	"time"

	"gorm.io/gorm"
)

// ProxyConfigCache 反向代理配置缓存表
type ProxyConfigCache struct {
	ID          uint           `json:"id" gorm:"primaryKey"`
	NodeID      uint           `json:"node_id" gorm:"index;not null"`
	NodeName    string         `json:"node_name" gorm:"size:200"`
	Hostname    string         `json:"hostname" gorm:"index;size:200;not null"`
	Domain      string         `json:"domain" gorm:"size:500"`
	BackendPort int            `json:"backend_port"`
	SSLEnabled  bool           `json:"ssl_enabled"`
	Status      string         `json:"status" gorm:"size:50"`
	LastSync    time.Time      `json:"last_sync"`
	SyncError   string         `json:"sync_error" gorm:"type:text"`
	CreatedAt   time.Time      `json:"created_at"`
	UpdatedAt   time.Time      `json:"updated_at"`
	DeletedAt   gorm.DeletedAt `json:"-" gorm:"index"`
}

// ProxySyncTask Proxy同步任务表
type ProxySyncTask struct {
	ID           uint           `json:"id" gorm:"primaryKey"`
	NodeID       uint           `json:"node_id" gorm:"index"`
	NodeName     string         `json:"node_name" gorm:"size:200"`
	Status       string         `json:"status" gorm:"size:50"`
	TotalCount   int            `json:"total_count"`
	SuccessCount int            `json:"success_count"`
	FailedCount  int            `json:"failed_count"`
	ErrorMessage string         `json:"error_message" gorm:"type:text"`
	StartTime    *time.Time     `json:"start_time"`
	EndTime      *time.Time     `json:"end_time"`
	CreatedAt    time.Time      `json:"created_at"`
	DeletedAt    gorm.DeletedAt `json:"-" gorm:"index"`
}

