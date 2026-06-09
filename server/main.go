package main

import (
	"context"
	"crypto/tls"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/gorilla/websocket"
)

// --- Config from env ---
var (
	tvIP        string
	tvMAC       string
	tvPort      int
	serverPort  int
	appName     string
	tokenFile   string
	encodedName string
)

// --- App icon domain mapping ---
var appDomains = map[string]string{
	"YouTube":                  "youtube.com",
	"Netflix":                  "netflix.com",
	"Disney+":                  "disneyplus.com",
	"Prime Video":              "primevideo.com",
	"Apple TV":                 "tv.apple.com",
	"Apple Music":              "music.apple.com",
	"Spotify":                  "spotify.com",
	"Spotify – hudba a podcasty": "spotify.com",
	"Plex":                     "plex.tv",
	"Jellyfin":                 "jellyfin.org",
	"HBO Max":                  "max.com",
	"O2 TV":                    "o2tv.cz",
	"O2 TV (Legacy)":           "o2tv.cz",
	"Prima+":                   "primaplus.cz",
	"SkyShowtime":              "skyshowtime.com",
	"Rakuten TV":               "rakuten.tv",
	"CANAL+ App":               "canalplus.com",
	"Skylink CZ":               "skylink.cz",
	"MAGENTA TV":               "magentatv.cz",
	"MALL.TV":                  "mall.tv",
	"Lepší.TV / goNET.TV":      "lepsi.tv",
	"SWEET.TV":                 "sweet.tv",
	"JOJ Play":                 "play.joj.sk",
	"Voyo.sk":                  "voyo.sk",
	"Oneplay":                  "oneplay.cz",
	"HbbTV":                    "hbbtv.org",
}

type app struct {
	AppID string `json:"appId"`
	Name  string `json:"name"`
}

// --- TV connection state (guarded by mu) ---
var (
	mu             sync.Mutex
	writeMu        sync.Mutex
	conn           *websocket.Conn
	connected      bool
	connecting     bool
	reconnectDelay = 5 * time.Second
	appsWaiters    []chan []app
	heldTimers     = map[string]*time.Timer{}
)

const maxReconnectDelay = 60 * time.Second

func tvURL() string {
	token := ""
	if b, err := os.ReadFile(tokenFile); err == nil {
		token = strings.TrimSpace(string(b))
	}
	base := fmt.Sprintf("wss://%s:%d/api/v2/channels/samsung.remote.control?name=%s", tvIP, tvPort, encodedName)
	if token != "" {
		return base + "&token=" + token
	}
	return base
}

func scheduleReconnect() {
	mu.Lock()
	d := reconnectDelay
	reconnectDelay = min(reconnectDelay*2, maxReconnectDelay)
	mu.Unlock()
	time.AfterFunc(d, connectToTV)
}

func connectToTV() {
	mu.Lock()
	if connected || connecting {
		mu.Unlock()
		return
	}
	connecting = true
	mu.Unlock()

	log.Printf("Connecting to TV at %s...", tvIP)
	dialer := websocket.Dialer{
		TLSClientConfig:  &tls.Config{InsecureSkipVerify: true},
		HandshakeTimeout: 10 * time.Second,
	}
	c, _, err := dialer.Dial(tvURL(), nil)
	if err != nil {
		log.Printf("Connect failed: %v", err)
		mu.Lock()
		connecting = false
		mu.Unlock()
		scheduleReconnect()
		return
	}
	log.Println("Connected to TV!")
	mu.Lock()
	conn = c
	mu.Unlock()

	go readLoop(c)

	// Watchdog: if ms.channel.connect never arrives, force a reconnect.
	time.AfterFunc(10*time.Second, func() {
		mu.Lock()
		stuck := !connected && conn == c
		mu.Unlock()
		if stuck {
			c.Close()
		}
	})
}

func readLoop(c *websocket.Conn) {
	defer func() {
		mu.Lock()
		if conn == c {
			conn = nil
			connected = false
			connecting = false
		}
		mu.Unlock()
		log.Printf("Disconnected from TV, reconnecting in %v...", reconnectDelay)
		scheduleReconnect()
	}()
	for {
		_, data, err := c.ReadMessage()
		if err != nil {
			return
		}
		handleMessage(data)
	}
}

func handleMessage(b []byte) {
	var m struct {
		Event string          `json:"event"`
		Data  json.RawMessage `json:"data"`
	}
	if json.Unmarshal(b, &m) != nil {
		return
	}
	var d struct {
		Token string `json:"token"`
		Data  []app  `json:"data"`
	}
	if len(m.Data) > 0 {
		_ = json.Unmarshal(m.Data, &d)
	}

	if d.Token != "" {
		if err := os.WriteFile(tokenFile, []byte(d.Token), 0o644); err != nil {
			log.Printf("Failed to save token: %v", err)
		} else {
			log.Println("Token saved")
		}
	}

	if m.Event == "ms.channel.connect" {
		mu.Lock()
		connected = true
		connecting = false
		reconnectDelay = 5 * time.Second
		mu.Unlock()
		log.Println("TV ready")
	}

	if m.Event == "ed.installedApp.get" {
		mu.Lock()
		waiters := appsWaiters
		appsWaiters = nil
		mu.Unlock()
		for _, ch := range waiters {
			ch <- d.Data
		}
	}
}

// --- TV commands ---
func wsSend(v any) bool {
	mu.Lock()
	c, ok := conn, connected
	mu.Unlock()
	if c == nil || !ok {
		go connectToTV()
		return false
	}
	b, _ := json.Marshal(v)
	writeMu.Lock()
	defer writeMu.Unlock()
	return c.WriteMessage(websocket.TextMessage, b) == nil
}

// Cmd "Click" = single press; "Press"/"Release" = hold (the TV ramps its own
// repeat, e.g. faster seeking) just like the physical remote.
func sendKeyCmd(key, cmd string) bool {
	return wsSend(map[string]any{
		"method": "ms.remote.control",
		"params": map[string]any{
			"Cmd":          cmd,
			"DataOfCmd":    key,
			"Option":       "false",
			"TypeOfRemote": "SendRemoteKey",
		},
	})
}

func sendKey(key string) bool { return sendKeyCmd(key, "Click") }

func launchApp(appID string) bool {
	return wsSend(map[string]any{
		"method": "ms.channel.emit",
		"params": map[string]any{
			"event": "ed.apps.launch",
			"to":    "host",
			"data":  map[string]any{"appId": appID, "action_type": "DEEP_LINK"},
		},
	})
}

// --- Press-and-hold safety ---
// A held key is auto-released if the client stops pinging (tab closed, network
// dropped, phone slept) so the TV can't get stuck with a key held forever. The
// client keeps holding by pinging keyhold, which re-arms this timer.
const holdSafety = 5 * time.Second

func armRelease(key string) {
	mu.Lock()
	defer mu.Unlock()
	if t, ok := heldTimers[key]; ok {
		t.Stop()
	}
	heldTimers[key] = time.AfterFunc(holdSafety, func() {
		mu.Lock()
		delete(heldTimers, key)
		mu.Unlock()
		sendKeyCmd(key, "Release")
		log.Printf("Auto-release (timeout): %s", key)
	})
}

func pressKey(key string) bool {
	if !sendKeyCmd(key, "Press") {
		return false
	}
	armRelease(key)
	return true
}

func holdKey(key string) {
	mu.Lock()
	_, held := heldTimers[key]
	mu.Unlock()
	if held {
		armRelease(key)
	}
}

func releaseKey(key string) bool {
	mu.Lock()
	if t, ok := heldTimers[key]; ok {
		t.Stop()
		delete(heldTimers, key)
	}
	mu.Unlock()
	return sendKeyCmd(key, "Release")
}

// --- Wake-on-LAN ---
func sendWol() {
	if tvMAC == "" {
		log.Println("TV_MAC not set — WoL skipped.")
		return
	}
	hw, err := net.ParseMAC(tvMAC)
	if err != nil {
		log.Printf("Bad TV_MAC: %v", err)
		return
	}
	packet := make([]byte, 102)
	for i := 0; i < 6; i++ {
		packet[i] = 0xff
	}
	for i := 0; i < 16; i++ {
		copy(packet[6+i*6:], hw)
	}

	// Broadcast-enabled UDP socket.
	lc := net.ListenConfig{Control: func(_, _ string, c syscall.RawConn) error {
		var serr error
		c.Control(func(fd uintptr) {
			serr = syscall.SetsockoptInt(int(fd), syscall.SOL_SOCKET, syscall.SO_BROADCAST, 1)
		})
		return serr
	}}
	pc, err := lc.ListenPacket(context.Background(), "udp4", ":0")
	if err != nil {
		log.Printf("WoL socket error: %v", err)
		return
	}
	defer pc.Close()

	broadcast := subnetBroadcast(tvIP)
	targets := []string{"255.255.255.255", broadcast, tvIP}
	ports := []int{9, 7}
	for attempt := 0; attempt < 3; attempt++ {
		for _, t := range targets {
			for _, p := range ports {
				if addr, err := net.ResolveUDPAddr("udp4", fmt.Sprintf("%s:%d", t, p)); err == nil {
					pc.WriteTo(packet, addr)
				}
			}
		}
		time.Sleep(500 * time.Millisecond)
	}
	log.Println("WoL sent (3x to broadcast + subnet + unicast)")
}

func subnetBroadcast(ip string) string {
	if i := strings.LastIndex(ip, "."); i >= 0 {
		return ip[:i] + ".255"
	}
	return "255.255.255.255"
}

// --- Apps (fan-out + coalesce + timeout) ---
func getApps() ([]app, error) {
	mu.Lock()
	if conn == nil || !connected {
		mu.Unlock()
		go connectToTV()
		return nil, fmt.Errorf("TV not connected")
	}
	ch := make(chan []app, 1)
	alreadyPending := len(appsWaiters) > 0
	appsWaiters = append(appsWaiters, ch)
	c := conn
	mu.Unlock()

	if !alreadyPending {
		b, _ := json.Marshal(map[string]any{
			"method": "ms.channel.emit",
			"params": map[string]any{"event": "ed.installedApp.get", "to": "host"},
		})
		writeMu.Lock()
		c.WriteMessage(websocket.TextMessage, b)
		writeMu.Unlock()
	}

	select {
	case apps := <-ch:
		return apps, nil
	case <-time.After(5 * time.Second):
		mu.Lock()
		appsWaiters = removeChan(appsWaiters, ch)
		mu.Unlock()
		return nil, fmt.Errorf("Timeout")
	}
}

func removeChan(s []chan []app, ch chan []app) []chan []app {
	out := s[:0]
	for _, c := range s {
		if c != ch {
			out = append(out, c)
		}
	}
	return out
}

// --- Real power state ---
// The WS stays "connected" even in standby, so it can't tell on from standby.
// The REST endpoint reports the actual PowerState.
func getPowerState() string {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	req, _ := http.NewRequestWithContext(ctx, "GET", fmt.Sprintf("http://%s:8001/api/v2/", tvIP), nil)
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		return "off"
	}
	defer res.Body.Close()
	var info struct {
		Device struct {
			PowerState string `json:"PowerState"`
		} `json:"device"`
	}
	if json.NewDecoder(res.Body).Decode(&info) != nil {
		return "off"
	}
	if info.Device.PowerState == "on" {
		return "on"
	}
	return "off"
}

// --- Icon proxy with cache ---
type icon struct {
	body  []byte
	ctype string
}

var (
	iconMu    sync.Mutex
	iconCache = map[string]icon{}
)

func fetchIcon(name string) (icon, bool) {
	iconMu.Lock()
	if ic, ok := iconCache[name]; ok {
		iconMu.Unlock()
		return ic, true
	}
	iconMu.Unlock()

	domain, ok := appDomains[name]
	if !ok {
		return icon{}, false
	}
	res, err := http.Get(fmt.Sprintf("https://www.google.com/s2/favicons?domain=%s&sz=128", domain))
	if err != nil {
		return icon{}, false
	}
	defer res.Body.Close()
	if res.StatusCode != 200 {
		return icon{}, false
	}
	body, err := io.ReadAll(res.Body)
	if err != nil {
		return icon{}, false
	}
	ct := res.Header.Get("Content-Type")
	if ct == "" {
		ct = "image/png"
	}
	ic := icon{body, ct}
	iconMu.Lock()
	iconCache[name] = ic
	iconMu.Unlock()
	return ic, true
}

// --- Static assets ---
type asset struct {
	body  []byte
	ctype string
}

var assets = map[string]asset{}

func loadAssets() {
	files := map[string]struct{ path, ctype string }{
		"favicon.svg":          {"client/icons/favicon.svg", "image/svg+xml"},
		"favicon-32.png":       {"client/icons/favicon-32.png", "image/png"},
		"apple-touch-icon.png": {"client/icons/apple-touch-icon.png", "image/png"},
		"icon-192.png":         {"client/icons/icon-192.png", "image/png"},
		"icon-512.png":         {"client/icons/icon-512.png", "image/png"},
		"manifest.webmanifest": {"client/manifest.webmanifest", "application/manifest+json"},
	}
	for name, f := range files {
		if b, err := os.ReadFile(f.path); err == nil {
			assets[name] = asset{b, f.ctype}
		}
	}
}

// --- HTTP helpers ---
func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func serveAsset(name string) http.HandlerFunc {
	return func(w http.ResponseWriter, _ *http.Request) {
		a, ok := assets[name]
		if !ok {
			w.WriteHeader(http.StatusNotFound)
			return
		}
		w.Header().Set("Content-Type", a.ctype)
		w.Header().Set("Cache-Control", "public, max-age=604800")
		w.Write(a.body)
	}
}

func getenv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func atoiEnv(key string, def int) int {
	if v := os.Getenv(key); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return def
}

func main() {
	tvIP = os.Getenv("TV_IP")
	if tvIP == "" {
		log.Fatal("Missing required env var TV_IP (see .env.example).")
	}
	tvMAC = os.Getenv("TV_MAC")
	tvPort = atoiEnv("TV_PORT", 8002)
	serverPort = atoiEnv("SERVER_PORT", 3000)
	appName = getenv("APP_NAME", "TVRemote")
	tokenFile = getenv("TOKEN_FILE", "./data/tv-token.txt")
	encodedName = base64.StdEncoding.EncodeToString([]byte(appName))

	html, err := os.ReadFile("client/index.html")
	if err != nil {
		log.Fatalf("Cannot read client/index.html: %v", err)
	}
	loadAssets()

	connectToTV()
	go keepAlive()

	mux := http.NewServeMux()

	mux.HandleFunc("GET /{$}", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.Write(html)
	})

	mux.HandleFunc("GET /favicon.svg", serveAsset("favicon.svg"))
	mux.HandleFunc("GET /favicon.ico", serveAsset("favicon-32.png"))
	mux.HandleFunc("GET /favicon-32.png", serveAsset("favicon-32.png"))
	mux.HandleFunc("GET /apple-touch-icon.png", serveAsset("apple-touch-icon.png"))
	mux.HandleFunc("GET /apple-touch-icon-precomposed.png", serveAsset("apple-touch-icon.png"))
	mux.HandleFunc("GET /icon-192.png", serveAsset("icon-192.png"))
	mux.HandleFunc("GET /icon-512.png", serveAsset("icon-512.png"))
	mux.HandleFunc("GET /manifest.webmanifest", serveAsset("manifest.webmanifest"))

	mux.HandleFunc("GET /api/status", func(w http.ResponseWriter, _ *http.Request) {
		mu.Lock()
		c := connected
		mu.Unlock()
		writeJSON(w, 200, map[string]any{"connected": c})
	})

	mux.HandleFunc("GET /api/tv-info", func(w http.ResponseWriter, _ *http.Request) {
		mu.Lock()
		isConn := connected
		mu.Unlock()
		power := "off"
		if isConn {
			power = getPowerState()
		}
		var activeApp any
		if power == "on" {
			if apps, err := getApps(); err == nil {
				activeApp = firstVisibleApp(apps)
			}
		}
		writeJSON(w, 200, map[string]any{"power": power, "activeApp": activeApp})
	})

	mux.HandleFunc("GET /api/reconnect", func(w http.ResponseWriter, _ *http.Request) {
		go connectToTV()
		writeJSON(w, 200, map[string]any{"ok": true})
	})

	mux.HandleFunc("GET /api/key/{key}", func(w http.ResponseWriter, r *http.Request) {
		key := r.PathValue("key")
		// Power must use the real power state: the WS stays connected in standby,
		// and this TV won't wake from standby over the WS — only Wake-on-LAN does.
		if key == "KEY_POWER" && getPowerState() == "off" {
			if tvMAC == "" {
				writeJSON(w, 503, map[string]any{"ok": false, "error": "WoL not configured (missing TV_MAC)"})
				return
			}
			go sendWol()
			time.AfterFunc(3*time.Second, func() { go connectToTV() })
			writeJSON(w, 200, map[string]any{"ok": true, "key": "WOL"})
			return
		}
		if !sendKey(key) {
			writeJSON(w, 503, map[string]any{"ok": false, "error": "TV not connected"})
			return
		}
		log.Printf("Sent: %s", key)
		writeJSON(w, 200, map[string]any{"ok": true, "key": key})
	})

	mux.HandleFunc("GET /api/keydown/{key}", func(w http.ResponseWriter, r *http.Request) {
		if pressKey(r.PathValue("key")) {
			writeJSON(w, 200, map[string]any{"ok": true})
		} else {
			writeJSON(w, 503, map[string]any{"ok": false, "error": "TV not connected"})
		}
	})

	mux.HandleFunc("GET /api/keyhold/{key}", func(w http.ResponseWriter, r *http.Request) {
		holdKey(r.PathValue("key"))
		writeJSON(w, 200, map[string]any{"ok": true})
	})

	mux.HandleFunc("GET /api/keyup/{key}", func(w http.ResponseWriter, r *http.Request) {
		if releaseKey(r.PathValue("key")) {
			writeJSON(w, 200, map[string]any{"ok": true})
		} else {
			writeJSON(w, 503, map[string]any{"ok": false, "error": "TV not connected"})
		}
	})

	mux.HandleFunc("GET /api/apps", func(w http.ResponseWriter, _ *http.Request) {
		apps, err := getApps()
		if err != nil {
			writeJSON(w, 503, map[string]any{"ok": false, "error": err.Error()})
			return
		}
		writeJSON(w, 200, map[string]any{"ok": true, "apps": apps})
	})

	mux.HandleFunc("GET /api/launch/{appId}", func(w http.ResponseWriter, r *http.Request) {
		if launchApp(r.PathValue("appId")) {
			writeJSON(w, 200, map[string]any{"ok": true})
		} else {
			writeJSON(w, 503, map[string]any{"ok": false, "error": "TV not connected"})
		}
	})

	mux.HandleFunc("GET /api/icon/{name...}", func(w http.ResponseWriter, r *http.Request) {
		ic, ok := fetchIcon(r.PathValue("name"))
		if !ok {
			w.WriteHeader(http.StatusNotFound)
			return
		}
		w.Header().Set("Content-Type", ic.ctype)
		w.Header().Set("Cache-Control", "public, max-age=86400")
		w.Write(ic.body)
	})

	addr := fmt.Sprintf("0.0.0.0:%d", serverPort)
	log.Printf("Server running on http://%s", addr)
	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatal(err)
	}
}

// firstVisibleApp checks all apps in parallel and returns the first visible one
// (by list order) — total wait is ~one timeout, not N.
func firstVisibleApp(apps []app) any {
	names := make([]string, len(apps))
	var wg sync.WaitGroup
	for i, a := range apps {
		wg.Add(1)
		go func(i int, id string) {
			defer wg.Done()
			ctx, cancel := context.WithTimeout(context.Background(), 800*time.Millisecond)
			defer cancel()
			req, _ := http.NewRequestWithContext(ctx, "GET", fmt.Sprintf("http://%s:8001/api/v2/applications/%s", tvIP, id), nil)
			res, err := http.DefaultClient.Do(req)
			if err != nil {
				return
			}
			defer res.Body.Close()
			var info struct {
				Name    string `json:"name"`
				Visible bool   `json:"visible"`
			}
			if json.NewDecoder(res.Body).Decode(&info) == nil && info.Visible {
				names[i] = info.Name
			}
		}(i, a.AppID)
	}
	wg.Wait()
	for _, n := range names {
		if n != "" {
			return n
		}
	}
	return nil
}

// --- Keep-alive ---
// The WS can stay half-open if the TV dies abruptly (no clean close), leaving
// connected stuck true — which would make the power button send a toggle instead
// of WoL. Probe the REST endpoint; after two misses, drop the state to reality.
func keepAlive() {
	misses := 0
	for range time.Tick(15 * time.Second) {
		mu.Lock()
		isConn := connected
		c := conn
		mu.Unlock()
		if !isConn {
			misses = 0
			continue
		}
		if restReachable() {
			misses = 0
			continue
		}
		misses++
		if misses < 2 {
			continue
		}
		misses = 0
		log.Println("Keep-alive failed — treating TV as disconnected.")
		mu.Lock()
		connected = false
		mu.Unlock()
		if c != nil {
			c.Close()
		}
	}
}

func restReachable() bool {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	req, _ := http.NewRequestWithContext(ctx, "GET", fmt.Sprintf("http://%s:8001/api/v2/", tvIP), nil)
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		return false
	}
	res.Body.Close()
	return true
}
