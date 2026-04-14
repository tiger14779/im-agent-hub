package api

import (
	"crypto/rand"
	"encoding/hex"
	"time"

	"im-agent-hub/database"
	"im-agent-hub/model"
	"im-agent-hub/pkg"

	"github.com/gin-gonic/gin"
)

func generateGroupID() string {
	b := make([]byte, 6)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	return "group_" + hex.EncodeToString(b)
}

// groupItem is the API response shape for a single group.
type groupItem struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	OwnerID     string `json:"ownerId"`
	Dissolved   bool   `json:"dissolved"`
	MemberCount int    `json:"memberCount"`
	CreatedAt   string `json:"createdAt"`
}

func buildGroupItem(g model.Group) groupItem {
	var cnt int64
	database.DB.Model(&model.GroupMember{}).Where("group_id = ?", g.ID).Count(&cnt)
	return groupItem{
		ID:          g.ID,
		Name:        g.Name,
		OwnerID:     g.OwnerID,
		Dissolved:   g.Dissolved,
		MemberCount: int(cnt),
		CreatedAt:   g.CreatedAt.Format(time.RFC3339),
	}
}

// ── Admin handlers ───────────────────────────────────────────────────────────

// AdminListGroups handles GET /api/admin/groups
func AdminListGroups() gin.HandlerFunc {
	return func(c *gin.Context) {
		var groups []model.Group
		if err := database.DB.Order("created_at desc").Find(&groups).Error; err != nil {
			pkg.Fail(c, 500, err.Error())
			return
		}
		list := make([]groupItem, 0, len(groups))
		for _, g := range groups {
			list = append(list, buildGroupItem(g))
		}
		pkg.Success(c, gin.H{"list": list, "total": len(list)})
	}
}

// AdminCreateGroup handles POST /api/admin/groups
func AdminCreateGroup() gin.HandlerFunc {
	return func(c *gin.Context) {
		var req struct {
			Name    string `json:"name" binding:"required"`
			OwnerID string `json:"ownerId" binding:"required"`
		}
		if err := c.ShouldBindJSON(&req); err != nil {
			pkg.Fail(c, 400, "name and ownerId are required")
			return
		}
		// Verify owner exists
		var staff model.ServiceStaff
		if err := database.DB.First(&staff, "user_id = ?", req.OwnerID).Error; err != nil {
			pkg.Fail(c, 404, "service staff not found")
			return
		}
		g := model.Group{
			ID:      generateGroupID(),
			Name:    req.Name,
			OwnerID: req.OwnerID,
		}
		if err := database.DB.Create(&g).Error; err != nil {
			pkg.Fail(c, 500, err.Error())
			return
		}
		// Auto-add owner as member
		database.DB.Create(&model.GroupMember{
			GroupID:  g.ID,
			UserID:   req.OwnerID,
			Role:     "owner",
			JoinedAt: time.Now(),
		})
		pkg.Success(c, buildGroupItem(g))
	}
}

// AdminDeleteGroup handles DELETE /api/admin/groups/:id  (dissolve)
func AdminDeleteGroup(chatHub *ChatHub) gin.HandlerFunc {
	return func(c *gin.Context) {
		id := c.Param("id")
		var g model.Group
		if err := database.DB.First(&g, "id = ?", id).Error; err != nil {
			pkg.Fail(c, 404, "group not found")
			return
		}
		// Mark dissolved
		database.DB.Model(&g).Update("dissolved", true)
		// Mark conversation dissolved
		database.DB.Model(&model.Conversation{}).Where("group_id = ?", id).Update("dissolved", true)
		// Notify all online members
		chatHub.broadcastGroupEvent(id, "group_dissolved", map[string]interface{}{
			"groupId": id,
		})
		pkg.Success(c, nil)
	}
}

// ── Service (PC staff) handlers ──────────────────────────────────────────────

// ServiceListGroups handles GET /api/service/groups
func ServiceListGroups() gin.HandlerFunc {
	return func(c *gin.Context) {
		staffID := c.GetString("serviceUserId")

		// Get groups where this staff is a member
		var members []model.GroupMember
		database.DB.Where("user_id = ?", staffID).Find(&members)
		groupIDs := make([]string, 0, len(members))
		for _, m := range members {
			groupIDs = append(groupIDs, m.GroupID)
		}
		if len(groupIDs) == 0 {
			pkg.Success(c, gin.H{"list": []interface{}{}, "total": 0})
			return
		}

		var groups []model.Group
		database.DB.Where("id IN ?", groupIDs).Order("created_at desc").Find(&groups)

		// For each group, include member list with nicknames
		type memberInfo struct {
			UserID    string `json:"userId"`
			Nickname  string `json:"nickname"`
			AvatarUrl string `json:"avatarUrl"`
			Role      string `json:"role"`
		}
		type groupWithMembers struct {
			groupItem
			Members []memberInfo `json:"members"`
		}

		list := make([]groupWithMembers, 0, len(groups))
		for _, g := range groups {
			var gms []model.GroupMember
			database.DB.Where("group_id = ?", g.ID).Find(&gms)

			mlist := make([]memberInfo, 0, len(gms))
			for _, gm := range gms {
				mi := memberInfo{UserID: gm.UserID, Role: gm.Role}
				// Try User table first, then ServiceStaff
				var u model.User
				if err := database.DB.First(&u, "id = ?", gm.UserID).Error; err == nil {
					mi.Nickname = u.Nickname
					mi.AvatarUrl = u.Avatar
				} else {
					var s model.ServiceStaff
					if err2 := database.DB.First(&s, "user_id = ?", gm.UserID).Error; err2 == nil {
						mi.Nickname = s.Nickname
						mi.AvatarUrl = s.Avatar
					}
				}
				mlist = append(mlist, mi)
			}

			list = append(list, groupWithMembers{
				groupItem: buildGroupItem(g),
				Members:   mlist,
			})
		}
		pkg.Success(c, gin.H{"list": list, "total": len(list)})
	}
}

// ServiceInviteToGroup handles POST /api/service/groups/:id/members
func ServiceInviteToGroup(chatHub *ChatHub) gin.HandlerFunc {
	return func(c *gin.Context) {
		staffID := c.GetString("serviceUserId")
		groupID := c.Param("id")

		var req struct {
			UserID string `json:"userId" binding:"required"`
		}
		if err := c.ShouldBindJSON(&req); err != nil {
			pkg.Fail(c, 400, "userId is required")
			return
		}

		// Verify group exists and belongs to this staff
		var g model.Group
		if err := database.DB.First(&g, "id = ? AND dissolved = false", groupID).Error; err != nil {
			pkg.Fail(c, 404, "group not found or dissolved")
			return
		}
		if g.OwnerID != staffID {
			pkg.Fail(c, 403, "only the group owner can invite members")
			return
		}

		// Check user exists under this staff
		var user model.User
		if err := database.DB.First(&user, "id = ? AND service_user_id = ? AND status = 1", req.UserID, staffID).Error; err != nil {
			pkg.Fail(c, 404, "user not found under this staff")
			return
		}

		// Check not already a member
		var existing model.GroupMember
		if err := database.DB.First(&existing, "group_id = ? AND user_id = ?", groupID, req.UserID).Error; err == nil {
			pkg.Fail(c, 409, "user already in group")
			return
		}

		database.DB.Create(&model.GroupMember{
			GroupID:  groupID,
			UserID:   req.UserID,
			Role:     "member",
			JoinedAt: time.Now(),
		})

		// Notify new member and all online group members
		chatHub.broadcastGroupEvent(groupID, "group_member_added", map[string]interface{}{
			"groupId":   groupID,
			"groupName": g.Name,
			"userId":    req.UserID,
			"nickname":  user.GroupNickname,
		})

		pkg.Success(c, buildGroupItem(g))
	}
}

// ServiceDissolveGroup handles DELETE /api/service/groups/:id
// Only the group owner (staff) can dissolve the group.
func ServiceDissolveGroup(chatHub *ChatHub) gin.HandlerFunc {
	return func(c *gin.Context) {
		staffID := c.GetString("serviceUserId")
		groupID := c.Param("id")

		var g model.Group
		if err := database.DB.First(&g, "id = ? AND dissolved = false", groupID).Error; err != nil {
			pkg.Fail(c, 404, "group not found or already dissolved")
			return
		}
		if g.OwnerID != staffID {
			pkg.Fail(c, 403, "only the group owner can dissolve the group")
			return
		}

		// Mark group dissolved
		database.DB.Model(&g).Update("dissolved", true)
		// Mark conversations dissolved
		database.DB.Model(&model.Conversation{}).Where("group_id = ?", groupID).Update("dissolved", true)
		// Notify all online members
		chatHub.broadcastGroupEvent(groupID, "group_dissolved", map[string]interface{}{
			"groupId": groupID,
		})
		pkg.Success(c, nil)
	}
}

// ServiceKickFromGroup handles DELETE /api/service/groups/:id/members/:userId
func ServiceKickFromGroup(chatHub *ChatHub) gin.HandlerFunc {
	return func(c *gin.Context) {
		staffID := c.GetString("serviceUserId")
		groupID := c.Param("id")
		targetUserID := c.Param("userId")

		// Verify group
		var g model.Group
		if err := database.DB.First(&g, "id = ? AND dissolved = false", groupID).Error; err != nil {
			pkg.Fail(c, 404, "group not found or dissolved")
			return
		}
		if g.OwnerID != staffID {
			pkg.Fail(c, 403, "only the group owner can kick members")
			return
		}
		// Cannot kick owner
		if targetUserID == staffID {
			pkg.Fail(c, 400, "cannot kick the group owner")
			return
		}

		result := database.DB.Delete(&model.GroupMember{}, "group_id = ? AND user_id = ?", groupID, targetUserID)
		if result.RowsAffected == 0 {
			pkg.Fail(c, 404, "member not found in group")
			return
		}

		chatHub.broadcastGroupEvent(groupID, "group_member_removed", map[string]interface{}{
			"groupId": groupID,
			"userId":  targetUserID,
		})

		pkg.Success(c, buildGroupItem(g))
	}
}
