package api

import (
	"io"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

// LotteryLatest proxies the external lottery API to avoid browser CORS issues.
// GET /api/lottery/latest
func LotteryLatest() gin.HandlerFunc {
	client := &http.Client{Timeout: 10 * time.Second}

	return func(c *gin.Context) {
		resp, err := client.Get("https://api.api68.com/CQShiCai/getBaseCQShiCaiList.do?lotCode=10010")
		if err != nil {
			c.JSON(http.StatusBadGateway, gin.H{"error": "failed to fetch lottery data"})
			return
		}
		defer resp.Body.Close()

		c.Header("Content-Type", "application/json; charset=utf-8")
		c.Status(resp.StatusCode)
		io.Copy(c.Writer, resp.Body)
	}
}
