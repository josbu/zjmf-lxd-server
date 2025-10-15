package models

import (
	"time"

	"gorm.io/gorm"
)

// IPv6BindingCache IPv6绑定缓存表
type IPv6BindingCache struct {
	ID          uint           `json:"id" gorm:"primaryKey"`
	NodeID      uint           `json:"node_id" gorm:"index;not null"`
	NodeName    string         `json:"node_name" gorm:"size:200"`
	Hostname    string         `json:"hostname" gorm:"index;size:200;not null"`
	IPv6Address string         `json:"ipv6_address" gorm:"size:100"`
	Interface   string         `json:"interface" gorm:"size:50"`
	Status      string         `json:"status" gorm:"size:50"`
	LastSync    time.Time      `json:"last_sync"`
	SyncError   string         `json:"sync_error" gorm:"type:text"`
	CreatedAt   time.Time      `json:"created_at"`
	UpdatedAt   time.Time      `json:"updated_at"`
	DeletedAt   gorm.DeletedAt `json:"-" gorm:"index"`
}

// IPv6SyncTask IPv6同步任务表
type IPv6SyncTask struct {
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

