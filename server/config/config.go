package config

import (
	"log"
	"os"
	"path/filepath"
	"strings"

	"github.com/spf13/viper"
)

type Config struct {
	Server     ServerConfig     `mapstructure:"server"`
	Admin      AdminConfig      `mapstructure:"admin"`
	Cleanup    CleanupConfig    `mapstructure:"cleanup"`
	Database   DatabaseConfig   `mapstructure:"database"`
	VoiceRelay VoiceRelayConfig `mapstructure:"voice_relay"`
}

// VoiceRelayConfig configures the WebSocket audio relay endpoint.
// All servers share the same HMAC secret to generate/validate short-lived
// audio tokens without inter-server API calls.
type VoiceRelayConfig struct {
	// Secret is the HMAC-SHA256 key shared across all servers.
	Secret string `mapstructure:"secret"`
	// RelayWsUrl is the audio relay WebSocket base URL.
	// Empty string means "use this server itself" (constructed from request Host).
	// Other servers set this to wss://jp.your-domain.com/api/call/audio
	RelayWsUrl string `mapstructure:"relay_ws_url"`
}

type ServerConfig struct {
	Port      int    `mapstructure:"port"`
	JWTSecret string `mapstructure:"jwt_secret"`
}

type AdminConfig struct {
	Username string `mapstructure:"username"`
	Password string `mapstructure:"password"`
}

type CleanupConfig struct {
	Enabled       bool   `mapstructure:"enabled"`
	RetentionDays int    `mapstructure:"retention_days"`
	Cron          string `mapstructure:"cron"`
}

type DatabaseConfig struct {
	Host     string `mapstructure:"host"`
	Port     int    `mapstructure:"port"`
	User     string `mapstructure:"user"`
	Password string `mapstructure:"password"`
	DBName   string `mapstructure:"dbname"`
}

// Cfg is the global configuration instance.
var Cfg *Config

// LoadConfig reads configuration. It always loads config.yaml as the base,
// then merges config.local.yaml on top if it exists.
func LoadConfig(path string) {
	viper.SetEnvKeyReplacer(strings.NewReplacer(".", "_"))
	viper.AutomaticEnv()

	// Always read the base config.yaml first
	baseDir := filepath.Dir(path)
	basePath := filepath.Join(baseDir, "config.yaml")
	viper.SetConfigFile(basePath)
	if err := viper.ReadInConfig(); err != nil {
		log.Fatalf("failed to read base config: %v", err)
	}

	// Merge local overrides if the file exists and is different from base
	localPath := filepath.Join(baseDir, "config.local.yaml")
	if localPath != basePath {
		if _, err := os.Stat(localPath); err == nil {
			viper.SetConfigFile(localPath)
			if err := viper.MergeInConfig(); err != nil {
				log.Printf("warn: failed to merge local config: %v", err)
			}
		}
	}

	Cfg = &Config{}
	if err := viper.Unmarshal(Cfg); err != nil {
		log.Fatalf("failed to unmarshal config: %v", err)
	}
}
