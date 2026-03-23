package api

import (
	"crypto/md5"
	"encoding/hex"
	"io"
	"log"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

const uploadDir = "./data/uploads"

// UploadFile stores uploaded files locally and returns a URL served by our
// own backend, completely bypassing the OpenIM / MinIO object storage.
func UploadFile() gin.HandlerFunc {
	// Ensure directory exists at startup.
	os.MkdirAll(uploadDir, 0o755)

	return func(c *gin.Context) {
		file, header, err := c.Request.FormFile("file")
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"code": 400, "msg": "缺少文件参数"})
			return
		}
		defer file.Close()

		data, err := io.ReadAll(file)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"code": 500, "msg": "读取文件失败"})
			return
		}

		// Build a unique path: data/uploads/2026/03/23/<md5hash><ext>
		hash := md5.Sum(data)
		hashStr := hex.EncodeToString(hash[:])
		ext := path.Ext(header.Filename)
		datePart := time.Now().Format("2006/01/02")
		relPath := filepath.Join(datePart, hashStr+ext)
		absPath := filepath.Join(uploadDir, relPath)

		// Create parent directories.
		if err := os.MkdirAll(filepath.Dir(absPath), 0o755); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"code": 500, "msg": "创建目录失败"})
			return
		}

		// Write file (skip if dedup hit).
		if _, err := os.Stat(absPath); os.IsNotExist(err) {
			if err := os.WriteFile(absPath, data, 0o644); err != nil {
				log.Printf("[upload] write failed: %v", err)
				c.JSON(http.StatusInternalServerError, gin.H{"code": 500, "msg": "写入文件失败"})
				return
			}
		}

		// Build the access URL relative to our own server.
		accessURL := "/api/files/" + strings.ReplaceAll(relPath, "\\", "/")

		log.Printf("[upload] success: name=%s size=%d url=%s", header.Filename, len(data), accessURL)
		c.JSON(http.StatusOK, gin.H{"code": 0, "msg": "ok", "data": gin.H{"url": accessURL}})
	}
}

// ServeUploadedFiles serves files from the local upload directory.
func ServeUploadedFiles() gin.HandlerFunc {
	return func(c *gin.Context) {
		filePath := c.Param("path")
		if filePath == "" {
			c.Status(http.StatusNotFound)
			return
		}
		filePath = strings.TrimPrefix(filePath, "/")

		// Prevent directory traversal.
		cleaned := filepath.Clean(filePath)
		if strings.Contains(cleaned, "..") {
			c.Status(http.StatusForbidden)
			return
		}

		absPath := filepath.Join(uploadDir, cleaned)
		if _, err := os.Stat(absPath); os.IsNotExist(err) {
			c.Status(http.StatusNotFound)
			return
		}

		c.File(absPath)
	}
}
