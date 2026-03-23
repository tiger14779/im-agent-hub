//go:build ignore

package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"time"

	"github.com/gorilla/websocket"
)

const baseURL = "http://localhost:8080"

func main() {
	fmt.Println("=== E2E Test: Login → WS → Message ===")

	// 1. Admin login
	fmt.Print("[1] Admin login... ")
	adminToken := mustPost("/api/admin/auth/login", map[string]interface{}{
		"username": "admin",
		"password": "admin123",
	}, "token")
	fmt.Println("OK, token:", adminToken[:20]+"...")

	// 2. Create service staff
	fmt.Print("[2] Create service staff... ")
	resp := mustPostFull("/api/admin/services", map[string]interface{}{
		"userId":   "staff_test01",
		"nickname": "测试客服",
	}, adminToken)
	fmt.Println("OK, staff:", resp["userId"])

	// 3. Create client user
	fmt.Print("[3] Create client user... ")
	resp = mustPostFull("/api/admin/users", map[string]interface{}{
		"nickname":      "测试用户",
		"serviceUserId": "staff_test01",
	}, adminToken)
	clientUserID := resp["id"].(string)
	fmt.Println("OK, userId:", clientUserID)

	// 4. Client login
	fmt.Print("[4] Client login... ")
	clientResp := mustPostFull("/api/client/auth/login", map[string]interface{}{
		"userId": clientUserID,
	}, "")
	clientToken := clientResp["token"].(string)
	fmt.Println("OK, token:", clientToken[:20]+"...")

	// 5. Staff login
	fmt.Print("[5] Staff login... ")
	staffResp := mustPostFull("/api/service/auth/login", map[string]interface{}{
		"userId": "staff_test01",
	}, "")
	staffToken := staffResp["token"].(string)
	fmt.Println("OK, token:", staffToken[:20]+"...")

	// 6. Staff WebSocket connect
	fmt.Print("[6] Staff WS connect... ")
	staffWS := mustWS("/api/service/ws", map[string]string{
		"staffId": "staff_test01",
		"token":   staffToken,
	})
	defer staffWS.Close()
	fmt.Println("OK")

	// 7. Client WebSocket connect
	fmt.Print("[7] Client WS connect... ")
	clientWS := mustWS("/api/ws", map[string]string{
		"userId": clientUserID,
		"token":  clientToken,
	})
	defer clientWS.Close()
	fmt.Println("OK")

	// 8. Client sends text message to staff
	fmt.Print("[8] Client sends text message... ")
	sendMsg := map[string]interface{}{
		"type": "send_message",
		"data": map[string]interface{}{
			"recvId":      "staff_test01",
			"contentType": 101,
			"content":     `{"text":"你好，我想咨询一下"}`,
			"clientMsgId": "test_msg_001",
		},
	}
	mustWriteJSON(clientWS, sendMsg)
	fmt.Println("sent")

	// 9. Client receives ACK
	fmt.Print("[9] Waiting for client ACK... ")
	ack := mustReadJSON(clientWS, 5*time.Second)
	fmt.Printf("type=%s, status=%v, serverMsgId=%v\n", ack["type"], getNestedField(ack, "data", "status"), getNestedField(ack, "data", "serverMsgId"))

	// 10. Staff receives new_message
	fmt.Print("[10] Waiting for staff new_message... ")
	newMsg := mustReadJSON(staffWS, 5*time.Second)
	fmt.Printf("type=%s, sendID=%v, content=%v\n", newMsg["type"], getNestedField(newMsg, "data", "sendID"), getNestedField(newMsg, "data", "content"))

	// 11. Staff replies
	fmt.Print("[11] Staff replies... ")
	replyMsg := map[string]interface{}{
		"type": "send_message",
		"data": map[string]interface{}{
			"recvId":      clientUserID,
			"contentType": 101,
			"content":     `{"text":"您好，请问有什么可以帮您？"}`,
			"clientMsgId": "test_msg_002",
		},
	}
	mustWriteJSON(staffWS, replyMsg)
	fmt.Println("sent")

	// 12. Staff receives ACK
	fmt.Print("[12] Waiting for staff ACK... ")
	staffAck := mustReadJSON(staffWS, 5*time.Second)
	fmt.Printf("type=%s, status=%v\n", staffAck["type"], getNestedField(staffAck, "data", "status"))

	// 13. Client receives the reply
	fmt.Print("[13] Waiting for client new_message... ")
	clientNewMsg := mustReadJSON(clientWS, 5*time.Second)
	fmt.Printf("type=%s, content=%v\n", clientNewMsg["type"], getNestedField(clientNewMsg, "data", "content"))

	// 14. Client loads history
	fmt.Print("[14] Client loads history... ")
	histReq := map[string]interface{}{
		"type": "load_history",
		"data": map[string]interface{}{
			"peerUserId": "staff_test01",
			"beforeSeq":  0,
			"limit":      50,
		},
	}
	mustWriteJSON(clientWS, histReq)
	histResp := mustReadJSON(clientWS, 5*time.Second)
	if histResp["type"] == "history" {
		data := histResp["data"].(map[string]interface{})
		msgs := data["messages"].([]interface{})
		fmt.Printf("OK, %d messages in history\n", len(msgs))
	} else {
		fmt.Printf("unexpected type: %s\n", histResp["type"])
	}

	// 15. Ping/Pong
	fmt.Print("[15] Ping/Pong test... ")
	mustWriteJSON(clientWS, map[string]interface{}{"type": "ping"})
	pong := mustReadJSON(clientWS, 5*time.Second)
	fmt.Printf("type=%s\n", pong["type"])

	fmt.Println("\n=== ALL TESTS PASSED ===")
}

func mustPost(path string, body map[string]interface{}, field string) string {
	resp := mustPostFull(path, body, "")
	return resp[field].(string)
}

func mustPostFull(path string, body map[string]interface{}, token string) map[string]interface{} {
	b, _ := json.Marshal(body)
	req, _ := http.NewRequest("POST", baseURL+path, bytes.NewReader(b))
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		fmt.Printf("FAIL: %v\n", err)
		os.Exit(1)
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 400 {
		fmt.Printf("FAIL: %d %s\n", resp.StatusCode, string(raw))
		os.Exit(1)
	}
	var envelope struct {
		Code int                    `json:"code"`
		Msg  string                 `json:"msg"`
		Data map[string]interface{} `json:"data"`
	}
	if err := json.Unmarshal(raw, &envelope); err != nil {
		fmt.Printf("FAIL: bad json: %s\n", string(raw))
		os.Exit(1)
	}
	if envelope.Code != 0 {
		fmt.Printf("FAIL: code=%d msg=%s\n", envelope.Code, envelope.Msg)
		os.Exit(1)
	}
	return envelope.Data
}

func mustWS(path string, params map[string]string) *websocket.Conn {
	u := url.URL{Scheme: "ws", Host: "localhost:8080", Path: path}
	q := u.Query()
	for k, v := range params {
		q.Set(k, v)
	}
	u.RawQuery = q.Encode()
	conn, _, err := websocket.DefaultDialer.Dial(u.String(), nil)
	if err != nil {
		fmt.Printf("FAIL: ws dial %s: %v\n", path, err)
		os.Exit(1)
	}
	return conn
}

func mustWriteJSON(conn *websocket.Conn, v interface{}) {
	if err := conn.WriteJSON(v); err != nil {
		fmt.Printf("FAIL: ws write: %v\n", err)
		os.Exit(1)
	}
}

func mustReadJSON(conn *websocket.Conn, timeout time.Duration) map[string]interface{} {
	conn.SetReadDeadline(time.Now().Add(timeout))
	_, raw, err := conn.ReadMessage()
	if err != nil {
		fmt.Printf("FAIL: ws read: %v\n", err)
		os.Exit(1)
	}
	var result map[string]interface{}
	if err := json.Unmarshal(raw, &result); err != nil {
		fmt.Printf("FAIL: ws bad json: %s\n", string(raw))
		os.Exit(1)
	}
	return result
}

func getNestedField(m map[string]interface{}, keys ...string) interface{} {
	current := interface{}(m)
	for _, k := range keys {
		if mp, ok := current.(map[string]interface{}); ok {
			current = mp[k]
		} else {
			return nil
		}
	}
	return current
}
