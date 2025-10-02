package handlers
import (
	"lxdweb/database"
	"lxdweb/models"
	"net/http"
	"github.com/gin-contrib/sessions"
	"github.com/gin-gonic/gin"
)
func LoginPage(c *gin.Context) {
	session := sessions.Default(c)
	if adminID := session.Get("admin_id"); adminID != nil {
		c.Redirect(http.StatusFound, "/dashboard")
		return
	}
	c.HTML(http.StatusOK, "login.html", gin.H{
		"title": "登录 - LXD管理后台",
	})
}
func Login(c *gin.Context) {
	var req struct {
		Username string `json:"username" form:"username" binding:"required"`
		Password string `json:"password" form:"password" binding:"required"`
		Captcha  string `json:"captcha" form:"captcha" binding:"required"`
	}
	if err := c.ShouldBind(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"code": 400,
			"msg":  "请填写完整信息",
		})
		return
	}
	session := sessions.Default(c)
	captchaID := session.Get("captcha_id")
	if captchaID == nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"code": 400,
			"msg":  "验证码已过期，请刷新",
		})
		return
	}
	if !VerifyCaptcha(captchaID.(string), req.Captcha) {
		c.JSON(http.StatusBadRequest, gin.H{
			"code": 400,
			"msg":  "验证码错误",
		})
		return
	}
	session.Delete("captcha_id")
	session.Save()
	var admin models.Admin
	if err := database.DB.Where("username = ?", req.Username).First(&admin).Error; err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{
			"code": 401,
			"msg":  "用户名或密码错误",
		})
		return
	}
	if !admin.CheckPassword(req.Password) {
		c.JSON(http.StatusUnauthorized, gin.H{
			"code": 401,
			"msg":  "用户名或密码错误",
		})
		return
	}
	session.Set("admin_id", admin.ID)
	session.Set("username", admin.Username)
	if err := session.Save(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"code": 500,
			"msg":  "登录失败",
		})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"code": 200,
		"msg":  "登录成功",
		"data": gin.H{
			"redirect": "/dashboard",
		},
	})
}
func Logout(c *gin.Context) {
	session := sessions.Default(c)
	session.Clear()
	session.Save()
	c.Redirect(http.StatusFound, "/login")
}
