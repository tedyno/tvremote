package main

import (
	"crypto/tls"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"os"
	"sort"
	"strings"
	"time"

	"github.com/gorilla/websocket"
)

var keys = map[string]string{
	"mute":   "KEY_MUTE",
	"up":     "KEY_VOLUP",
	"down":   "KEY_VOLDOWN",
	"power":  "KEY_POWER",
	"chup":   "KEY_CHUP",
	"chdown": "KEY_CHDOWN",
	"enter":  "KEY_ENTER",
	"back":   "KEY_RETURN",
	"home":   "KEY_HOME",
	"source": "KEY_SOURCE",
	"menu":   "KEY_MENU",
	"play":   "KEY_PLAY",
	"pause":  "KEY_PAUSE",
	"stop":   "KEY_STOP",
}

func getenv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func main() {
	tvIP := os.Getenv("TV_IP")
	if tvIP == "" {
		fmt.Println("Missing required env var TV_IP (see .env.example).")
		os.Exit(1)
	}
	tvPort := getenv("TV_PORT", "8002")
	appName := getenv("APP_NAME", "TVRemote")
	tokenFile := getenv("TOKEN_FILE", "./data/tv-token.txt")

	var cmd string
	if len(os.Args) > 1 {
		cmd = strings.ToLower(os.Args[1])
	}
	key, ok := keys[cmd]
	if !ok {
		names := make([]string, 0, len(keys))
		for k := range keys {
			names = append(names, k)
		}
		sort.Strings(names)
		fmt.Println("Usage: go run ./server/cli <command>")
		fmt.Printf("Available commands: %s\n", strings.Join(names, ", "))
		os.Exit(1)
	}

	name := base64.StdEncoding.EncodeToString([]byte(appName))
	url := fmt.Sprintf("wss://%s:%s/api/v2/channels/samsung.remote.control?name=%s", tvIP, tvPort, name)
	if b, err := os.ReadFile(tokenFile); err == nil {
		if t := strings.TrimSpace(string(b)); t != "" {
			url += "&token=" + t
		}
	}

	dialer := websocket.Dialer{
		TLSClientConfig:  &tls.Config{InsecureSkipVerify: true},
		HandshakeTimeout: 10 * time.Second,
	}
	fmt.Printf("Connecting to TV at %s...\n", tvIP)
	c, _, err := dialer.Dial(url, nil)
	if err != nil {
		fmt.Printf("Connection error: %v\n", err)
		os.Exit(1)
	}
	defer c.Close()
	fmt.Println("Connected to TV!")

	for {
		_, data, err := c.ReadMessage()
		if err != nil {
			fmt.Printf("Connection error: %v\n", err)
			os.Exit(1)
		}
		var m struct {
			Event string `json:"event"`
			Data  struct {
				Token string `json:"token"`
			} `json:"data"`
		}
		if json.Unmarshal(data, &m) != nil {
			continue
		}
		if m.Data.Token != "" {
			os.WriteFile(tokenFile, []byte(m.Data.Token), 0o644)
			fmt.Println("Token saved to", tokenFile)
		}
		if m.Event == "ms.channel.connect" {
			payload, _ := json.Marshal(map[string]any{
				"method": "ms.remote.control",
				"params": map[string]any{
					"Cmd": "Click", "DataOfCmd": key, "Option": "false", "TypeOfRemote": "SendRemoteKey",
				},
			})
			c.WriteMessage(websocket.TextMessage, payload)
			fmt.Printf("Sent: %s\n", key)
			time.Sleep(time.Second)
			return
		}
	}
}
