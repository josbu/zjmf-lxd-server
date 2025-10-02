package handlers
import (
	"net/http"
	"github.com/gin-contrib/sessions"
	"github.com/gin-gonic/gin"
)
func DashboardPage(c *gin.Context) {
	session := sessions.Default(c)
	username := session.Get("username")
	c.HTML(http.StatusOK, "dashboard.html", gin.H{
		"title":    "仪表盘 - LXD管理后台",
		"username": username,
	})
}
