package api

import (
	"net/http"
	"strings"

	"im-agent-hub/config"
	"im-agent-hub/pkg"

	"github.com/gin-gonic/gin"
)

// JWTAuth validates the Bearer token and stores claims in the context.
func JWTAuth() gin.HandlerFunc {
	return func(c *gin.Context) {
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, pkg.Response{Code: 401, Msg: "missing authorization header"})
			return
		}

		parts := strings.SplitN(authHeader, " ", 2)
		if len(parts) != 2 || !strings.EqualFold(parts[0], "bearer") {
			c.AbortWithStatusJSON(http.StatusUnauthorized, pkg.Response{Code: 401, Msg: "invalid authorization format"})
			return
		}

		claims, err := pkg.ParseToken(parts[1], config.Cfg.Server.JWTSecret)
		if err != nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, pkg.Response{Code: 401, Msg: "invalid or expired token"})
			return
		}

		c.Set("userID", claims.UserID)
		c.Set("isAdmin", claims.IsAdmin)
		c.Next()
	}
}

// AdminRequired ensures the authenticated user is an admin.
func AdminRequired() gin.HandlerFunc {
	return func(c *gin.Context) {
		isAdmin, _ := c.Get("isAdmin")
		if v, ok := isAdmin.(bool); !ok || !v {
			c.AbortWithStatusJSON(http.StatusForbidden, pkg.Response{Code: 403, Msg: "admin access required"})
			return
		}
		c.Next()
	}
}
