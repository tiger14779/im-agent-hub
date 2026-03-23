package config

import (
	"log"
	"strings"

	"github.com/spf13/viper"
)

type Config struct {
	Server  ServerConfig  `mapstructure:"server"`
	OpenIM  OpenIMConfig  `mapstructure:"openim"`
	Admin   AdminConfig   `mapstructure:"admin"`
	Cleanup CleanupConfig `mapstructure:"cleanup"`
}

type ServerConfig struct {
	Port      int    `mapstructure:"port"`
	JWTSecret string `mapstructure:"jwt_secret"`
}

type OpenIMConfig struct {
	APIURL      string `mapstructure:"api_url"`
	WSURL       string `mapstructure:"ws_url"`
	AdminUserID string `mapstructure:"admin_user_id"`
	Secret      string `mapstructure:"secret"`
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

// Cfg is the global configuration instance.
var Cfg *Config

// LoadConfig reads configuration from the given path.
func LoadConfig(path string) {
	viper.SetConfigFile(path)
	viper.SetEnvKeyReplacer(strings.NewReplacer(".", "_"))
	viper.AutomaticEnv()

	if err := viper.ReadInConfig(); err != nil {
		log.Fatalf("failed to read config: %v", err)
	}

	Cfg = &Config{}
	if err := viper.Unmarshal(Cfg); err != nil {
		log.Fatalf("failed to unmarshal config: %v", err)
	}
}
