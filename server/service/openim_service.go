package service

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"sync"
	"time"
)

// OpenIMService wraps HTTP calls to the OpenIM server.
type OpenIMService struct {
	apiURL      string
	adminUserID string
	secret      string

	mu          sync.Mutex
	adminToken  string
	tokenExpiry time.Time
}

// NewOpenIMService creates a new service instance.
func NewOpenIMService(apiURL, adminUserID, secret string) *OpenIMService {
	return &OpenIMService{
		apiURL:      apiURL,
		adminUserID: adminUserID,
		secret:      secret,
	}
}

// post sends a JSON POST request to the given OpenIM endpoint.
func (s *OpenIMService) post(path string, body interface{}, headers map[string]string) ([]byte, error) {
	data, err := json.Marshal(body)
	if err != nil {
		return nil, fmt.Errorf("marshal request: %w", err)
	}

	req, err := http.NewRequest(http.MethodPost, s.apiURL+path, bytes.NewReader(data))
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	for k, v := range headers {
		req.Header.Set(k, v)
	}

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("execute request: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read response: %w", err)
	}
	return respBody, nil
}

// getAdminToken returns a cached admin token, refreshing it when expired.
func (s *OpenIMService) getAdminToken() (string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.adminToken != "" && time.Now().Before(s.tokenExpiry) {
		return s.adminToken, nil
	}

	type reqBody struct {
		Secret      string `json:"secret"`
		PlatformID  int    `json:"platformID"`
		AdminUserID string `json:"userID"`
	}
	type respData struct {
		Token  string `json:"token"`
		Expire int64  `json:"expireTimeSeconds"`
	}
	type apiResp struct {
		ErrCode int      `json:"errCode"`
		ErrMsg  string   `json:"errMsg"`
		Data    respData `json:"data"`
	}

	raw, err := s.post("/auth/get_admin_token", reqBody{
		Secret:      s.secret,
		PlatformID:  1,
		AdminUserID: s.adminUserID,
	}, nil)
	if err != nil {
		return "", err
	}

	var result apiResp
	if err := json.Unmarshal(raw, &result); err != nil {
		return "", fmt.Errorf("parse admin token response: %w", err)
	}
	if result.ErrCode != 0 {
		return "", fmt.Errorf("get_admin_token error %d: %s", result.ErrCode, result.ErrMsg)
	}

	s.adminToken = result.Data.Token
	// Refresh 60 seconds before actual expiry to avoid race conditions.
	s.tokenExpiry = time.Now().Add(time.Duration(result.Data.Expire-60) * time.Second)
	return s.adminToken, nil
}

// authHeader builds the Authorization header map for authenticated requests.
func (s *OpenIMService) authHeader() (map[string]string, error) {
	token, err := s.getAdminToken()
	if err != nil {
		return nil, err
	}
	return map[string]string{"token": token}, nil
}

// RegisterUser registers a new user in OpenIM.
func (s *OpenIMService) RegisterUser(userID, nickname string) error {
	headers, err := s.authHeader()
	if err != nil {
		return err
	}

	type userInfo struct {
		UserID   string `json:"userID"`
		Nickname string `json:"nickname"`
	}
	type reqBody struct {
		Users []userInfo `json:"users"`
	}
	type apiResp struct {
		ErrCode int    `json:"errCode"`
		ErrMsg  string `json:"errMsg"`
	}

	raw, err := s.post("/user/user_register", reqBody{
		Users: []userInfo{{UserID: userID, Nickname: nickname}},
	}, headers)
	if err != nil {
		return err
	}

	var result apiResp
	if err := json.Unmarshal(raw, &result); err != nil {
		return fmt.Errorf("parse register response: %w", err)
	}
	if result.ErrCode != 0 {
		return fmt.Errorf("user_register error %d: %s", result.ErrCode, result.ErrMsg)
	}
	return nil
}

// GetUserToken obtains an OpenIM token for a regular user (platformID=5, web).
func (s *OpenIMService) GetUserToken(userID string) (string, error) {
	headers, err := s.authHeader()
	if err != nil {
		return "", err
	}

	type reqBody struct {
		UserID     string `json:"userID"`
		PlatformID int    `json:"platformID"`
	}
	type respData struct {
		Token string `json:"token"`
	}
	type apiResp struct {
		ErrCode int      `json:"errCode"`
		ErrMsg  string   `json:"errMsg"`
		Data    respData `json:"data"`
	}

	raw, err := s.post("/auth/user_token", reqBody{
		UserID:     userID,
		PlatformID: 5,
	}, headers)
	if err != nil {
		return "", err
	}

	var result apiResp
	if err := json.Unmarshal(raw, &result); err != nil {
		return "", fmt.Errorf("parse user token response: %w", err)
	}
	if result.ErrCode != 0 {
		return "", fmt.Errorf("user_token error %d: %s", result.ErrCode, result.ErrMsg)
	}
	return result.Data.Token, nil
}

// GetOnlineUsers returns the count of currently online users.
func (s *OpenIMService) GetOnlineUsers(userIDs []string) (int, error) {
	headers, err := s.authHeader()
	if err != nil {
		return 0, err
	}

	type reqBody struct {
		UserIDs []string `json:"userIDs"`
	}
	type statusItem struct {
		Status int `json:"status"`
	}
	type respData struct {
		SuccessResult []statusItem `json:"successResult"`
	}
	type apiResp struct {
		ErrCode int      `json:"errCode"`
		ErrMsg  string   `json:"errMsg"`
		Data    respData `json:"data"`
	}

	raw, err := s.post("/user/get_users_online_status", reqBody{UserIDs: userIDs}, headers)
	if err != nil {
		return 0, err
	}

	var result apiResp
	if err := json.Unmarshal(raw, &result); err != nil {
		return 0, fmt.Errorf("parse online status response: %w", err)
	}
	if result.ErrCode != 0 {
		return 0, fmt.Errorf("get_users_online_status error %d: %s", result.ErrCode, result.ErrMsg)
	}

	online := 0
	for _, item := range result.Data.SuccessResult {
		if item.Status == 1 {
			online++
		}
	}
	return online, nil
}

// DeleteMessages clears conversation messages older than the given timestamp for a user.
func (s *OpenIMService) DeleteMessages(userID string, before time.Time) error {
	headers, err := s.authHeader()
	if err != nil {
		return err
	}

	type reqBody struct {
		UserID string `json:"userID"`
		Before int64  `json:"clearTime"` // Unix milliseconds
	}
	type apiResp struct {
		ErrCode int    `json:"errCode"`
		ErrMsg  string `json:"errMsg"`
	}

	raw, err := s.post("/msg/clear_conversation_msg", reqBody{
		UserID: userID,
		Before: before.UnixMilli(),
	}, headers)
	if err != nil {
		return err
	}

	var result apiResp
	if err := json.Unmarshal(raw, &result); err != nil {
		return fmt.Errorf("parse clear messages response: %w", err)
	}
	if result.ErrCode != 0 {
		return fmt.Errorf("clear_conversation_msg error %d: %s", result.ErrCode, result.ErrMsg)
	}
	return nil
}
