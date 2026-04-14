package service

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"

	"im-agent-hub/database"
	"im-agent-hub/model"
)

// UserService handles user business logic.
type UserService struct{}

// NewUserService creates a UserService.
func NewUserService() *UserService {
	return &UserService{}
}

// generateUserID produces a cryptographically random user ID in the form "user_xxxxxxxx".
func generateUserID() string {
	b := make([]byte, 4)
	if _, err := rand.Read(b); err != nil {
		panic("crypto/rand unavailable: " + err.Error())
	}
	return "user_" + hex.EncodeToString(b)
}

// CreateUser creates a new user in the local DB.
func (s *UserService) CreateUser(nickname, groupNickname, serviceUserID string) (*model.User, error) {
	user := &model.User{
		ID:            generateUserID(),
		Nickname:      nickname,
		GroupNickname: groupNickname,
		ServiceUserID: serviceUserID,
		Status:        1,
	}

	if err := database.DB.Create(user).Error; err != nil {
		return nil, fmt.Errorf("create user in db: %w", err)
	}

	return user, nil
}

// DeleteUser removes a user from the local DB.
func (s *UserService) DeleteUser(id string) error {
	result := database.DB.Delete(&model.User{}, "id = ?", id)
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected == 0 {
		return errors.New("user not found")
	}
	return nil
}

// GetUsers returns a paginated list of users and the total count.
func (s *UserService) GetUsers(page, pageSize int) ([]model.User, int64, error) {
	var users []model.User
	var total int64

	offset := (page - 1) * pageSize

	if err := database.DB.Model(&model.User{}).Count(&total).Error; err != nil {
		return nil, 0, err
	}
	if err := database.DB.Order("created_at desc").Offset(offset).Limit(pageSize).Find(&users).Error; err != nil {
		return nil, 0, err
	}
	return users, total, nil
}

// UpdateUser modifies an existing user's nickname and/or service assignment.
func (s *UserService) UpdateUser(id, nickname, groupNickname, serviceUserID string) (*model.User, error) {
	var user model.User
	if err := database.DB.First(&user, "id = ?", id).Error; err != nil {
		return nil, errors.New("user not found")
	}

	user.Nickname = nickname
	user.GroupNickname = groupNickname
	user.ServiceUserID = serviceUserID

	if err := database.DB.Save(&user).Error; err != nil {
		return nil, err
	}
	return &user, nil
}

// GetUserByID fetches a single user by its ID.
func (s *UserService) GetUserByID(id string) (*model.User, error) {
	var user model.User
	if err := database.DB.First(&user, "id = ?", id).Error; err != nil {
		return nil, errors.New("user not found")
	}
	return &user, nil
}

// UpdateAvatar sets the avatar URL for a user.
func (s *UserService) UpdateAvatar(id, avatar string) {
	database.DB.Model(&model.User{}).Where("id = ?", id).Update("avatar", avatar)
}

// BatchCreateUsers creates multiple users assigned to the same service staff.
func (s *UserService) BatchCreateUsers(count int, serviceUserID string) ([]model.User, error) {
	users := make([]model.User, 0, count)
	for i := 0; i < count; i++ {
		u, err := s.CreateUser(fmt.Sprintf("用户%d", i+1), "无昵称", serviceUserID)
		if err != nil {
			return users, err
		}
		users = append(users, *u)
	}
	return users, nil
}
