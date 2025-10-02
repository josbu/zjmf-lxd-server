package config
import (
	"crypto/rand"
	"fmt"
	"log"
	"os"
	"gopkg.in/yaml.v3"
)
type Config struct {
	Server   ServerConfig   `yaml:"server"`
	Database DatabaseConfig `yaml:"database"`
	Sync     SyncConfig     `yaml:"sync"`
}
type ServerConfig struct {
	Address       string `yaml:"address"`
	Mode          string `yaml:"mode"`
	SessionSecret string `yaml:"session_secret"`
}
type DatabaseConfig struct {
	Path string `yaml:"path"`
}
type SyncConfig struct {
	Interval      int `yaml:"interval"`
	BatchSize     int `yaml:"batch_size"`
	BatchInterval int `yaml:"batch_interval"`
}
var AppConfig *Config
func LoadConfig() error {
	configFile := "config.yaml"
	if _, err := os.Stat(configFile); os.IsNotExist(err) {
		if err := createDefaultConfig(configFile); err != nil {
			return err
		}
	}
	data, err := os.ReadFile(configFile)
	if err != nil {
		return err
	}
	AppConfig = &Config{}
	if err := yaml.Unmarshal(data, AppConfig); err != nil {
		return err
	}
	if AppConfig.Server.Address == "" {
		AppConfig.Server.Address = "0.0.0.0:3000"
	}
	if AppConfig.Server.Mode == "" {
		AppConfig.Server.Mode = "release"
	}
	if AppConfig.Server.SessionSecret == "" {
		AppConfig.Server.SessionSecret = "lxdweb-secret-key-change-me"
	}
	if AppConfig.Database.Path == "" {
		AppConfig.Database.Path = "lxdweb.db"
	}
	if AppConfig.Sync.Interval <= 0 {
		AppConfig.Sync.Interval = 300  
	}
	if AppConfig.Sync.BatchSize <= 0 {
		AppConfig.Sync.BatchSize = 5
	}
	if AppConfig.Sync.BatchInterval <= 0 {
		AppConfig.Sync.BatchInterval = 2
	}
	log.Printf("✓ 配置加载完成: %s (同步间隔: %ds, 批量: %d个/批, 批次间隔: %ds)", 
		AppConfig.Server.Address, AppConfig.Sync.Interval, AppConfig.Sync.BatchSize, AppConfig.Sync.BatchInterval)
	return nil
}
func createDefaultConfig(filename string) error {
	sessionSecret := generateRandomString(64)
	defaultConfig := fmt.Sprintf(`server:
  address: "0.0.0.0:3000"
  mode: "release"
  session_secret: "%s"

database:
  path: "lxdweb.db"

sync:
  interval: 300
  batch_size: 5
  batch_interval: 2
`, sessionSecret)
	return os.WriteFile(filename, []byte(defaultConfig), 0600)
}
func generateRandomString(length int) string {
	const charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*"
	result := make([]byte, length)
	for i := range result {
		result[i] = charset[randomInt(len(charset))]
	}
	return string(result)
}
func randomInt(max int) int {
	b := make([]byte, 1)
	_, err := rand.Read(b)
	if err != nil {
		return 0
	}
	return int(b[0]) % max
}
