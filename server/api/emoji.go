package api

import (
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/gin-gonic/gin"
)

// emojiDir 表情资源目录（与 uploads 同级，便于 docker volume 挂载）
const emojiDir = "./data/Emoji"

// 允许的图片扩展名
var emojiAllowedExt = map[string]bool{
	".gif":  true,
	".png":  true,
	".jpg":  true,
	".jpeg": true,
	".bmp":  true,
	".webp": true,
}

// ListEmojis 列出 data/Emoji 下所有图片，返回访问 URL 与文件名
//
//	GET /api/emojis  →  {code:0, data:{emojis:[{name,url}]}}
func ListEmojis() gin.HandlerFunc {
	// 启动时确保目录存在
	_ = os.MkdirAll(emojiDir, 0o755)

	return func(c *gin.Context) {
		entries, err := os.ReadDir(emojiDir)
		if err != nil {
			c.JSON(http.StatusOK, gin.H{"code": 0, "msg": "ok", "data": gin.H{"emojis": []any{}}})
			return
		}
		type item struct {
			Name string `json:"name"`
			URL  string `json:"url"`
		}
		list := make([]item, 0, len(entries))
		for _, e := range entries {
			if e.IsDir() {
				continue
			}
			name := e.Name()
			ext := strings.ToLower(filepath.Ext(name))
			if !emojiAllowedExt[ext] {
				continue
			}
			list = append(list, item{
				Name: name,
				URL:  "/api/emojis/" + name,
			})
		}
		// 按文件名升序，前端再按用户 MRU 重排
		sort.Slice(list, func(i, j int) bool { return list[i].Name < list[j].Name })

		c.JSON(http.StatusOK, gin.H{"code": 0, "msg": "ok", "data": gin.H{"emojis": list}})
	}
}

// ServeEmoji 提供单个表情文件下载（带浏览器缓存头）
//
//	GET /api/emojis/:name
func ServeEmoji() gin.HandlerFunc {
	return func(c *gin.Context) {
		name := c.Param("name")
		if name == "" {
			c.Status(http.StatusNotFound)
			return
		}
		// 防止目录穿越
		cleaned := filepath.Clean(name)
		if strings.ContainsAny(cleaned, "/\\") || strings.Contains(cleaned, "..") {
			c.Status(http.StatusForbidden)
			return
		}
		ext := strings.ToLower(filepath.Ext(cleaned))
		if !emojiAllowedExt[ext] {
			c.Status(http.StatusForbidden)
			return
		}
		absPath := filepath.Join(emojiDir, cleaned)
		if fi, err := os.Stat(absPath); err != nil || fi.IsDir() {
			c.Status(http.StatusNotFound)
			return
		}
		// 表情文件名等于内容指纹（用户上传时即可保证），可强缓存 30 天
		c.Header("Cache-Control", "public, max-age=2592000, immutable")
		c.File(absPath)
	}
}
