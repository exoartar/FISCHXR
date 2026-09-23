;==============================================================================
; FISCHXR for AutoHotkey v2.0
;
; Automates the cast, shake and reel loop in the Roblox game Fisch by reading
; pixels on screen. It never touches game memory. Also feeds your aquarium,
; uses totems on a schedule, recharges Sovereign rods, sends Discord alerts
; and rejoins after a disconnect.
;
; Before you start
;   1. In Fisch's settings, set shake mode to Navigation.
;   2. Equip your rod and face the water.
;   3. Press F1 (or Start fishing). F1 again stops. F3 quits.
;
; Rod skins: the first reel with a new rod or skin is learned by watching
; which block of pixels moves with the bar, then kept as a rod look. The
; Rods tab lists them; the Live tab shows what the macro sees.
;
; Scan regions are stored as fractions of the Roblox window, so they adapt to
; any resolution. Library rod colours and the aquarium panel layout come from
; DeepFish v1.0.3 (github.com/yatonomacro/DeepFish).
;
; Settings save to FischMacro.ini next to this file.
;==============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent
SetWorkingDir A_ScriptDir
SendMode "Input"
SetMouseDelay -1
CoordMode "Mouse", "Screen"
CoordMode "Pixel", "Screen"
CoordMode "Menu", "Screen"
try ProcessSetPriority "AboveNormal"
UsePhysicalPixels()
DllCall("winmm\timeBeginPeriod", "UInt", 1)

APP_NAME := "FISCHXR"
APP_VER := "4.2.3"
UPDATE_URL := "https://raw.githubusercontent.com/exoartar/FISCHXR/main/update.json"
IniPath := A_ScriptDir "\FISCHXR.ini"
; Settings from before the rename come along once.
if (!FileExist(IniPath) && FileExist(A_ScriptDir "\FischMacro.ini"))
    try FileCopy(A_ScriptDir "\FischMacro.ini", IniPath)

;------------------------------------------------------------------------------
; Themes. Black is the default and uses only black, white and greys. Dark
; uses Windows 11 Notepad's greys with a teal accent.
;------------------------------------------------------------------------------
Themes := Map(
    "Black", {strip: "000000", bar: "0C0C0C", seam: "262626", content: "000000",
        field: "161616", fieldHi: "2A2A2A", divider: "303030",
        text: "FFFFFF", dim: "8C8C8C", faint: "4A4A4A",
        accent: "FFFFFF", accentHi: "D9D9D9", ink: "000000",
        wait: "BFBFBF", stop: "FFFFFF", focus: "FFFFFF", ring: 2, dark: true, mono: true},
    "Dark", {strip: "0A0A0A", bar: "1F1F1F", seam: "1C1C1C", content: "272727",
        field: "2F2F2F", fieldHi: "3B3B3B", divider: "323232",
        text: "F2F2F2", dim: "A8A8A8", faint: "707070",
        accent: "45E0C8", accentHi: "7AEEDC", ink: "03201B",
        wait: "F2B24C", stop: "FF7A6E", focus: "FFFFFF", ring: 2, dark: true},
    "Light", {strip: "EBEBEB", bar: "F7F7F7", seam: "DCDCDC", content: "FFFFFF",
        field: "EEEEEE", fieldHi: "E0E0E0", divider: "D4D4D4",
        text: "1A1A1A", dim: "5C5C5C", faint: "999999",
        accent: "00796B", accentHi: "00897B", ink: "FFFFFF",
        wait: "8F5500", stop: "C62828", focus: "000000", ring: 2, dark: false},
    "High contrast", {strip: "000000", bar: "000000", seam: "FFFFFF", content: "000000",
        field: "1C1C1C", fieldHi: "383838", divider: "FFFFFF",
        text: "FFFFFF", dim: "FFFFFF", faint: "C8C8C8",
        accent: "FFFF00", accentHi: "FFFF80", ink: "000000",
        wait: "00FFFF", stop: "FF6A6A", focus: "00FFFF", ring: 3, dark: true}
)
; Okabe-Ito based state colours that stay distinct with red-green colour blindness.
SafeColors := Map(
    "dark", {accent: "56B4E9", accentHi: "8ACCF1", ink: "04121C", wait: "F0E442", stop: "E8883A"},
    "light", {accent: "0072B2", accentHi: "0A82C4", ink: "FFFFFF", wait: "8A6100", stop: "B04A00"}
)

; Layout in design units. Everything is multiplied by the zoom level, and
; AutoHotkey then scales for the screen's DPI.
TAB_H := 0, BAR_H := 0, STATUS_H := 26
; Layout, in design units at 100% zoom. A sidebar of SIDEBAR_W width holds the
; tabs; pages sit to its right in one column of LEFT_W starting at PAGE_X. The
; row controls place themselves relative to PAD, shifted by ColX.
SIDEBAR_W := 136, NAV_H := 30, PAGE_X := SIDEBAR_W + 16
PAD := 24, LEFT_W := 456, DASH_X := PAGE_X, COL2 := PAGE_X
ROW_Y0 := 80, ROW_H := 34
MIN_W := 600, MIN_H := 400
BasicTabs := ["Home", "Fishing", "Totems", "Aquarium", "Sovereign", "Alerts", "Reconnect", "Settings"]
AdvTabs := ["Rods", "Live", "Reel", "Timing", "More"]
TabNames := ["Home", "Fishing", "Totems", "Aquarium", "Sovereign", "Alerts", "Reconnect", "Settings", "Rods", "Live", "Reel", "Timing", "More"]
WidePages := ""
ZoomSteps := [80, 90, 100, 110, 125, 150, 175, 200]
; Saved rod looks carry this number; looks with a lower one are relearned
; once (2: artwork printed on the bar is learned as bar, not as the fish).
LOOK_FORMAT := 2
; Where Fisch's own buttons sit, as offsets from the window's centre in
; window heights (across) and fractions of the height from the top (down).
; Fisch's interface scales with the window height, so these hold at any
; size. Measured on a 3838x2158 screen.
UiSpots := Map(
    "aquariums",  [0.0732, 0.0222],     ; the Aquariums tab at the top
    "enchantRod", [-0.0823, 0.6938],    ; inventory: Enchant Rod
    "search",     [0.0776, 0.7268],     ; inventory: the search box
    "firstItem",  [-0.1910, 0.7705],    ; inventory: the first slot
    "confirm",    [0.0524, 0.8397])     ; the "Enchant your Rod?" Confirm

; Totems the schedule can hold (name, night-only), and the Discord alert
; kinds with the setting that switches each on and its message title.
TotemPresets := [["Aurora", 1], ["Sundial", 0], ["Clearcast", 0], ["Tempest", 0], ["Windset", 0], ["Smokescreen", 0]
    , ["Eclipse", 0], ["Meteor", 0], ["Blizzard", 0], ["Avalanche", 0], ["Starfall", 0], ["Blue Moon", 1]
    , ["Zeus Storm", 0], ["Poseidon's Wrath", 0], ["Rainbow", 0], ["Mutation", 0], ["Shiny", 0], ["Sparkling", 0]]
TOTEM_MAX := 6
HookKinds := Map("start", "HookStart", "stop", "HookStart", "error", "HookErrors", "disconnect", "HookDisconnect"
    , "reconnect", "HookDisconnect", "aquarium", "HookJobs", "totem", "HookJobs", "sovereign", "HookJobs")
HookTitles := Map("start", "Fishing started", "stop", "Fishing stopped", "error", "Needs attention", "disconnect", "Disconnected"
    , "reconnect", "Back in the game", "aquarium", "Aquarium", "totem", "Totem", "sovereign", "Sovereign recharge"
    , "summary", "Session summary", "test", "Test alert")

;------------------------------------------------------------------------------
; Settings. Regions are fractions of the Roblox client area.
;------------------------------------------------------------------------------
Defaults := Map(
    "ToggleKey", "F1", "ExitKey", "F3", "RodKey", "1",
    "CastHold", 1000, "BobberWait", 1000, "BiteTimeout", 30, "CatchDelay", 1000, "RodReequip", 0,
    "ShakeMode", "Navigation", "ShakeInterval", 25, "UseNavKey", 0, "NavKey", "\", "ShakeTol", 3,
    "ControlStyle", "physics", "Latency", 0, "Braking", 100, "Predict", 70,
    "EdgeMargin", 8, "ScanDelay", 4, "LearnedLag", 0, "FishLead", 70,
    "ReelX1", 0.30157, "ReelY1", 0.84239, "ReelX2", 0.69847, "ReelY2", 0.86866,
    "ShakeX1", 0.22, "ShakeY1", 0.10, "ShakeX2", 0.78, "ShakeY2", 0.75,
    "AqAuto", 0, "AqEvery", 63, "AqMaxUses", 12, "AqMaxBuys", 8, "AqStepDelay", 320,
    "AqOpenWait", 1500, "AqScrollSteps", 14,
    "Theme", "Black", "Zoom", 100, "ColorSafe", 0, "ReduceMotion", 0, "Speak", 0, "Sounds", 0,
    "ShowSplash", 1, "ShowHome", 1, "OnTop", 1, "ShowAreas", 0, "LastTab", "Fishing",
    "WinX", "", "WinY", "", "WinW", 624, "WinH", 416,
    "TotemAuto", 0, "TotemWait", 2500, "TotemSundial", 1, "NightLevel", 70,
    "SovAuto", 0, "SovEvery", 20, "SovCount", 1, "SovInvKey", "``", "SovStep", 350, "SovOpenWait", 900,
    "HookUrl", "", "HookUser", "", "HookStart", 1, "HookErrors", 1, "HookDisconnect", 1, "HookJobs", 0,
    "HookSummary", 60, "HookShots", 1,
    "AutoReconnect", 0, "RejoinLink", "roblox://experiences/start?placeId=16732694052", "RejoinWait", 40,
    "RejoinMax", 4, "RejoinResume", 1, "ReelSnaps", 1,
    "MiniHud", 1, "UpdateUrl", UPDATE_URL, "AutoUpdate", 1, "LastVersion", ""
)
TextKeys := "|ToggleKey|ExitKey|RodKey|ShakeMode|NavKey|ControlStyle|Theme|LastTab|WinX|WinY|SovInvKey|HookUrl|HookUser|RejoinLink|UpdateUrl|LastVersion|"
BoolKeys := ["RodReequip", "UseNavKey", "AqAuto", "ColorSafe", "ReduceMotion", "Speak", "Sounds", "ShowSplash", "ShowHome", "OnTop", "ShowAreas"
    , "TotemAuto", "TotemSundial", "SovAuto", "HookStart", "HookErrors", "HookDisconnect", "HookJobs", "HookShots", "AutoReconnect", "RejoinResume", "ReelSnaps", "MiniHud", "AutoUpdate"]

NumSpec := Map(
    "CastHold",      {label: "Cast hold",        unit: "ms",  min: 100, max: 3000, step: 50,  help: "How long the mouse is held to cast."},
    "BobberWait",    {label: "Wait after cast",  unit: "ms",  min: 0,   max: 5000, step: 100, help: "Pause after the cast so the bobber can land before shaking starts."},
    "BiteTimeout",   {label: "Recast after",     unit: "s",   min: 5,   max: 120,  step: 5,   help: "If no reel bar shows up in this time, the macro casts again."},
    "CatchDelay",    {label: "Pause after reel", unit: "ms",  min: 0,   max: 5000, step: 100, help: "Time to wait after a reel ends while the catch popup clears."},
    "ShakeInterval", {label: "Shake every",      unit: "ms",  min: 10,  max: 500,  step: 5,   help: "Time between Enter presses, or clicks in Click mode. Lower shakes faster."},
    "ShakeTol",      {label: "Button match",     unit: "",    min: 0,   max: 60,   step: 1,   help: "Click mode only. How far a pixel may be from pure white and still count as the shake button."},
    "Latency",       {label: "Latency",          unit: "ms",  min: 0,   max: 200,  step: 5,   help: "Auto measures the delay between the screen and Roblox reacting while you reel. Set a number to use your own; raise it if the bar keeps overshooting."},
    "Braking",       {label: "Braking margin",   unit: "%",   min: 50,  max: 250,  step: 5,   help: "Scales how early the bar brakes. Above 100 brakes sooner, below 100 later."},
    "Predict",       {label: "Look-ahead",       unit: "ms",  min: 0,   max: 400,  step: 5,   help: "Simple control style only. How far ahead the bar position is predicted."},
    "EdgeMargin",    {label: "Edge zone",        unit: "%",   min: 0,   max: 30,   step: 1,   help: "When the fish is this close to either end, the bar is pinned against that wall."},
    "ScanDelay",     {label: "Scan delay",       unit: "ms",  min: 1,   max: 50,   step: 1,   help: "Pause between reel scans. Lower reacts faster and uses more CPU."},
    "AqEvery",       {label: "Feed every",       unit: "min", min: 5,   max: 240,  step: 1,   help: "How often the aquarium routine runs between catches."},
    "AqMaxUses",     {label: "Max food per visit", unit: "",  min: 1,   max: 40,   step: 1,   help: "Upper limit on food cards used plus bought in one visit."},
    "AqMaxBuys",     {label: "Max buys per visit", unit: "",  min: 0,   max: 20,   step: 1,   help: "How many food cards may be bought per visit. Zero never buys."},
    "AqStepDelay",   {label: "Click spacing",    unit: "ms",  min: 100, max: 2000, step: 20,  help: "Pause after each click in the aquarium panel."},
    "AqOpenWait",    {label: "Panel open wait",  unit: "ms",  min: 300, max: 6000, step: 100, help: "Extra time allowed for the aquarium panel to open or close."},
    "Zoom",          {label: "Zoom",             unit: "%",   min: 80,  max: 200,  step: 10,  help: "Scales the whole window. Ctrl+plus, Ctrl+minus and Ctrl+0 also work."},
    "TotemWait",     {label: "Wait after using", unit: "ms",  min: 500, max: 10000, step: 100, help: "Time allowed for a totem's animation before the rod goes back in hand."},
    "NightLevel",    {label: "Night below",      unit: "",    min: 5,   max: 250,  step: 5,   help: "Sky brightness under which it counts as night, for night-only totems. The current level shows below."},
    "SovEvery",      {label: "Recharge every",   unit: "reels", min: 1, max: 500,  step: 1,   help: "How many reels between Sovereign recharges. Only rods marked Sovereign are recharged."},
    "SovCount",      {label: "Relics per recharge", unit: "", min: 1,   max: 20,   step: 1,   help: "How many times Enchant Rod and Confirm are pressed per recharge. Each uses one relic."},
    "SovStep",       {label: "Click spacing",    unit: "ms",  min: 100, max: 3000, step: 50,  help: "Pause between the recharge clicks."},
    "SovOpenWait",   {label: "Inventory open wait", unit: "ms", min: 200, max: 5000, step: 100, help: "Time allowed for the inventory to open before the relic is picked."},
    "HookSummary",   {label: "Summary every",    unit: "min", min: 0,   max: 240,  step: 5,   help: "Sends a catch summary to Discord on this schedule while fishing. Off sends none."},
    "RejoinWait",    {label: "Load time",        unit: "s",   min: 10,  max: 180,  step: 5,   help: "How long to let Fisch load after Roblox reopens, before fishing resumes."},
    "RejoinMax",     {label: "Rejoins per hour", unit: "",    min: 1,   max: 20,   step: 1,   help: "After this many rejoins in an hour the macro stops, since something is wrong."}
)

;------------------------------------------------------------------------------
; Rod library. Each rod paints the reel bar and fish marker differently.
; In Auto mode every signature is tried when the reel starts, and an unknown
; rod has its colours learned by contrast against the track.
;------------------------------------------------------------------------------
; Built-in reel styles. The rod name read from the hotbar picks one; if it
; can't be read, the style that fits the reel is used. Nothing is learned or
; saved about rods. greenBar: green inside the bar counts as bar, and the
; fish is aimed at that green zone (Verdant Oath).
RodLib := [
    {id: "standard",    name: "Standard",               fish: ["434B5B"], ft: 5,  bar: ["F1F1F1", "848587"], bt: 6},
    {id: "verdant",     name: "Verdant Oath",           fish: ["434B5B"], ft: 12, bar: ["67512C", "65502D"], bt: 5, greenBar: true},
    {id: "halibut",     name: "Halibut Harpoon",        fish: ["0D0B0B"], ft: 5,  bar: ["5D52A8"], bt: 5},
    {id: "remembrance", name: "Remembrance",            fish: ["FFFFFF"], ft: 10, bar: ["B5B5B5"], bt: 10},
    {id: "departed",    name: "Remembrance (Departed)", fish: ["FFFFFF"], ft: 10, bar: ["474747"], bt: 8},
    {id: "migu",        name: "Migu Rod",               fish: ["F9D9D4", "FAD6CE", "F9D4C7", "F9D2C4", "F8D0B7"], ft: 10, bar: ["E9B681", "E0A66F", "D1935B"], bt: 8},
    {id: "noiseform",   name: "Noiseform",              kind: "box", fish: ["0C4125", "003820", "0D3A27"], ft: 8
        , bar: ["33A95F", "2C894D", "2AB778", "5CBD8C", "74C198", "60BC8E", "19B572", "010101"], bt: 10}
]

;------------------------------------------------------------------------------
; Runtime state
;------------------------------------------------------------------------------
Cfg := Map(), Dirty := Map(), RodMem := Map()
Pal := {}, Zoom := 1.0, HasIconFont := false, IconFace := ""
MainGui := 0, UiReady := false
UI := {}, Clickables := Map(), Pages := Map(), FocusGlobal := [], DescOf := Map()
Steppers := Map(), Toggles := Map(), KeyBtns := Map(), SegCtls := Map(), Swatches := Map(), Choices := Map()
Menus := Map(), Brushes := Map()
Stats := {casts: 0, reels: 0, misses: 0, start: 0}
Phase := {kind: "idle", title: "Ready", detail: ""}
Repeat := {key: "", dir: 0, hwnd: 0, n: 0}
Running := false, LoopActive := false, Calibrating := false, Capturing := false, MenuOpen := false
RobloxHwnd := 0, RobloxInfo := {found: false, w: 0, h: 0}
Hover := 0, CalFlag := "", FreezeHwnd := 0, NoSave := false, ResetArmed := false
OutReel := 0, OutShake := 0, OutAq := 0, CurTab := "Home"
CurRod := 0, SelRod := 0, RodProfiles := [], ProfSeq := 0, VisionLog := []
LiveBand := 0, LiveGeo := 0, LiveD := 0, LiveP := 0, LiveEp := -1, LiveT := 0, LiveHbm := 0, LiveRate := 0
UpdAllowLocal := false, UpdLast := ""
SessionLooks := Map(), CurRodName := "", CurRodLib := "", RodReadBusy := false, RodReadAt := 0, RodReadLast := "", OcrHook := 0
LivePreview := false, PreviewBand := 0, PreviewGeo := 0, EditCtls := Map(), ColX := 0, RowBase := 0
Totems := [], SovReels := 0, SovLast := ""
HookQueue := [], HookReq := 0, HookBusy := 0, HookLast := "", HookAllowLocal := false, HookItem := 0
ReconnectWhy := "", ReconnectTimes := [], RejoinHook := 0, LogDirOverride := "", LogConfirmMs := 12000
LogFile := "", LogPos := -1, LogPending := 0, LogJoinT := 0, LogTeleT := 0, LogLastLine := ""
AqNext := 0, AqManual := false, AqAbort := false, AqLast := ""
Events := [], FocusIdx := 0, FocusOn := false, Maxed := false, NormalRect := 0
Voice := 0, GaugeState := {l: 0.36, r: 0.64, f: 0.5, live: false}
RodInfoText := "Waiting for the first reel"

;------------------------------------------------------------------------------
; Startup: settings, loading screen, then the window with the start menu
;------------------------------------------------------------------------------
; An existing settings file means this is an upgrade (for What's new), and
; one saved before the sidebar layout gets the new, smaller window size.
WasExistingIni := FileExist(IniPath) != ""
OldLayout := WasExistingIni && IniRead(IniPath, "Settings", "UiVersion", 0) < 2
LoadSettings()
if OldLayout {
    Cfg["WinW"] := Defaults["WinW"], Cfg["WinH"] := Defaults["WinH"]
    try IniWrite(Cfg["WinW"], IniPath, "Settings", "WinW"), IniWrite(Cfg["WinH"], IniPath, "Settings", "WinH")
}
try IniWrite(2, IniPath, "Settings", "UiVersion")
if (Trim(Cfg["UpdateUrl"]) = "")             ; an empty saved link means the built-in one
    Cfg["UpdateUrl"] := UPDATE_URL
LoadRodMemory()
LoadTotems()
ResolveTheme()
DetectIconFont()
OnMessage(0x0014, WM_ERASEBKGND)
OnMessage(0x0201, WM_LBUTTONDOWN)
OnMessage(0x0203, WM_LBUTTONDOWN)  ; fast second clicks arrive as double-clicks
OnMessage(0x0200, WM_MOUSEMOVE)
OnMessage(0x020A, WM_MOUSEWHEEL)
OnMessage(0x0020, WM_SETCURSOR)
OnMessage(0x0100, WM_KEYDOWN)       ; keys for this window arrive as messages: no keyboard hook
OnMessage(0x0104, WM_KEYDOWN)       ; Alt combinations and F10 arrive as system keys
OnMessage(0x0105, WM_SYSKEYUP)
OnExit(Cleanup)
Boot()
if !BindHotkeys() {
    Cfg["ToggleKey"] := Defaults["ToggleKey"], Cfg["ExitKey"] := Defaults["ExitKey"]
    BindHotkeys()
    UpdateStartControls()
}
SetupTray()
SetTimer(WhatsNewCheck, -1500)
if (Cfg["AutoUpdate"] && Cfg["UpdateUrl"] != "")
    SetTimer(() => CheckForUpdate(true), -4000)
SetTimer(RefreshRobloxInfo, 2000)
if Cfg["ShowAreas"]
    SetTimer(UpdateOverlay, 500)

Boot() {
    show := Cfg["ShowSplash"]
    if show
        Splash.Show()
    steps := [
        ["Loading settings", 16, () => 0],
        ["Loading settings and totems", 34, () => 0],
        ["Looking for Roblox", 56, () => RefreshRobloxInfo()],
        ["Preparing detection", 74, () => 0],
        ["Building the window", 94, () => BuildGui()]
    ]
    for s in steps {
        if show
            Splash.Step(s[1], s[2])
        s[3].Call()
        if (show && !Cfg["ReduceMotion"])
            Sleep 110
    }
    if show {
        Splash.Step("Ready", 100)
        if !Cfg["ReduceMotion"]
            Sleep 160
    }
    ShowMain(Cfg["ShowHome"] ? "Home" : Cfg["LastTab"])
    if show
        Splash.Close()
    LogEvent("Opened")
}

; Loading screen: the logo on black with real startup steps and a progress
; line. It is a brand screen, so it stays black and white in every theme.
; The fish bobs gently while it loads unless motion is reduced.
class Splash {
    static g := 0, fill := 0, rest := 0, label := 0, pct := 0, x0 := 0, tw := 0, logo := 0, hbm := 0, ly := 0, t0 := 0
    static Show() {
        g := Gui("+AlwaysOnTop -Caption +ToolWindow", APP_NAME)
        g.BackColor := "000000"
        g.MarginX := 0, g.MarginY := 0
        W := ZS(480), L := ZS(176)
        this.ly := ZS(24)
        if (src := LogoImage("splash")) && (this.hbm := GpScaled(src, L, L, 0))
            this.logo := g.Add("Picture", Format("x{} y{} w{} h{}", (W - L) // 2, this.ly, L, L), "HBITMAP:*" this.hbm)
        SetFontFor(g, "norm s" FZ(20) " cFFFFFF q4", "display")
        g.Add("Text", Format("x0 y{} w{} Center Background000000", ZS(212), W), "F I S C H X R")
        SetFontFor(g, "norm s" FZ(9) " c8C8C8C q4", "body")
        g.Add("Text", Format("x0 y{} w{} Center Background000000", ZS(248), W), "v" APP_VER)
        this.x0 := ZS(90), this.tw := ZS(300)
        this.fill := g.Add("Text", Format("x{} y{} w1 h{} BackgroundFFFFFF", this.x0, ZS(282), ZS(2)))
        this.rest := g.Add("Text", Format("x{} y{} w{} h{} Background262626", this.x0 + 1, ZS(282), this.tw - 1, ZS(2)))
        SetFontFor(g, "norm s" FZ(9) " cBFBFBF q4", "body")
        this.label := g.Add("Text", Format("x0 y{} w{} Center Background000000", ZS(292), W), "Starting")
        SetFontFor(g, "norm s" FZ(8) " c5A5A5A q4", "body")
        g.Add("Text", Format("x0 y{} w{} Center Background000000", ZS(326), W)
            , KeyName(Cfg["ToggleKey"]) " starts and stops   ·   " KeyName(Cfg["ExitKey"]) " quits")
        g.Show(Format("w{} h{}", W, ZS(354)))
        StyleWindow(g.Hwnd)
        try ApplyAppIcon(g.Hwnd)
        this.g := g, this.pct := 0, this.t0 := A_TickCount
    }
    static Step(text, pct) {
        if !this.g
            return
        this.label.Text := text
        frames := Cfg["ReduceMotion"] ? 1 : 6
        from := this.pct
        Loop frames {
            p := from + (pct - from) * A_Index / frames
            fw := Max(1, Round(this.tw * p / 100))
            this.fill.Move(, , fw)
            this.rest.Move(this.x0 + fw, , Max(0, this.tw - fw))
            if (frames > 1) {
                if this.logo
                    this.logo.Move(, this.ly + Round(ZS(4) * Sin((A_TickCount - this.t0) / 260)))
                Sleep 16
            }
        }
        this.pct := pct
    }
    static Close() {
        if this.g {
            this.g.Destroy()
            this.g := 0
        }
        if this.hbm
            DllCall("DeleteObject", "Ptr", this.hbm), this.hbm := 0
        this.logo := 0
    }
}

;------------------------------------------------------------------------------
; Settings storage
;------------------------------------------------------------------------------
LoadSettings() {
    global Zoom
    for k, def in Defaults {
        v := IniRead(IniPath, "Settings", k, def)
        if !InStr(TextKeys, "|" k "|")
            v := IsNumber(v) ? v + 0 : def
        Cfg[k] := v
    }
    for k, sp in NumSpec
        Cfg[k] := Clamp(Round(Cfg[k]), sp.min, sp.max)
    for k in BoolKeys
        Cfg[k] := Cfg[k] ? 1 : 0
    if (Cfg["ShakeMode"] != "Navigation" && Cfg["ShakeMode"] != "Click")
        Cfg["ShakeMode"] := "Navigation"
    if (Cfg["ControlStyle"] != "physics" && Cfg["ControlStyle"] != "simple")
        Cfg["ControlStyle"] := "physics"
    if !Themes.Has(Cfg["Theme"])
        Cfg["Theme"] := "Black"
    old := Map("Cast", "Fishing", "Shake", "Fishing", "Accessibility", "Settings", "Setup", "Settings")
    if old.Has(Cfg["LastTab"])
        Cfg["LastTab"] := old[Cfg["LastTab"]]
    ok := false
    for t in TabNames
        ok := ok || (t = Cfg["LastTab"])
    if !ok
        Cfg["LastTab"] := "Fishing"

    for k in ["ToggleKey", "ExitKey", "RodKey", "NavKey"]
        if (Trim(Cfg[k]) = "")
            Cfg[k] := Defaults[k]
    for name in ["Reel", "Shake"] {
        good := true
        for k in ["X1", "Y1", "X2", "Y2"]
            if (Cfg[name k] < 0 || Cfg[name k] > 1)
                good := false
        if (!good || Cfg[name "X2"] - Cfg[name "X1"] < 0.02 || Cfg[name "Y2"] - Cfg[name "Y1"] < 0.002)
            for k in ["X1", "Y1", "X2", "Y2"]
                Cfg[name k] := Defaults[name k]
    }
    Cfg["WinW"] := Max(MIN_W, Cfg["WinW"]), Cfg["WinH"] := Max(MIN_H, Cfg["WinH"])
    Zoom := Cfg["Zoom"] / 100
}

Save(k) {
    Dirty[k] := true
    SetTimer(FlushSaves, -400)
}

FlushSaves() {
    if NoSave
        return
    for k in Dirty {
        v := Cfg[k]
        if RegExMatch(k, "^(Reel|Shake)[XY][12]$")
            v := Format("{:.5f}", v)
        try IniWrite(v, IniPath, "Settings", k)
    }
    Dirty.Clear()
}

; Learned bar physics per rod, keyed by rod and bar width: "standard@31=3.10,2.85,7"
LoadRodMemory() {
    try section := IniRead(IniPath, "Rods")
    catch
        return
    Loop Parse, section, "`n", "`r" {
        if !RegExMatch(A_LoopField, "^([\w-]+@\d+)=([\d.]+),([\d.]+),(\d+)$", &m)
            continue
        RodMem[m[1]] := {aH: m[2] + 0, aR: m[3] + 0, n: m[4] + 0}
    }
}

RememberRod(key, aH, aR) {
    n := RodMem.Has(key) ? RodMem[key].n + 1 : 1
    RodMem[key] := {aH: aH, aR: aR, n: n}
    if !NoSave
        try IniWrite(Format("{:.3f},{:.3f},{}", aH, aR, n), IniPath, "Rods", key)
}

ResolveTheme() {
    global Pal
    base := Themes[Cfg["Theme"]]
    Pal := {}
    for k, v in base.OwnProps()
        Pal.%k% := v
    if (Cfg["ColorSafe"] && !base.HasOwnProp("mono") && Cfg["Theme"] != "High contrast") {
        for k, v in SafeColors[base.dark ? "dark" : "light"].OwnProps()
            Pal.%k% := v
    }
}

; Library rods (their own reel colours), by id.
RodById(id) {
    for p in RodLib
        if (p.id = id)
            return p
    return {id: id, name: "Rod"}
}


;==============================================================================
; Macro control
;==============================================================================
ToggleMacro() {
    global AqAbort
    if (Calibrating || Capturing)
        return
    if AqManual {
        AqAbort := true
        return
    }
    if Running
        StopMacro()
    else if !LoopActive
        StartMacro()
}

StartMacro() {
    global Running, RobloxHwnd, SovReels, ReconnectWhy, LogFile
    UsePhysicalPixels()
    hwnd := FindRoblox()
    if !hwnd {
        SetPhase("error", "Roblox isn't open", "Open Fisch, then press " KeyName(Cfg["ToggleKey"]) ".")
        Cue("error")
        return
    }
    if PanelCoversReel(hwnd) {
        SetPhase("error", "Window is in the way", "Move this window off the reel bar, then start again.")
        Cue("error")
        return
    }
    RobloxHwnd := hwnd
    Running := true
    Stats.casts := 0, Stats.reels := 0, Stats.misses := 0, Stats.start := A_TickCount
    SovReels := 0, ReconnectWhy := "", LogFile := ""
    ScheduleTotems()
    UpdateStats()
    SetTimer(TickClock, 1000)
    if Cfg["AutoReconnect"]
        SetTimer(WatchConnection, 3000)
    if Cfg["HookSummary"]
        SetTimer(SummaryTick, Cfg["HookSummary"] * 60000)
    UpdateStartControls()
    HudEnter()
    SetTimer(ReadRodName, -400)            ; which rod is in hand
    LogEvent("Started fishing")
    Alert("start", "Fishing started" (IsObject(CurRod) ? " with " CurRod.name : "") ".")
    Cue("start")
    try WinActivate("ahk_id " hwnd)
    SetTimer(MacroLoop, -1)
}

StopMacro(msg := "") {
    global Running
    was := Running
    Running := false
    ReleaseMouse()
    SetTimer(TickClock, 0)
    SetTimer(WatchConnection, 0)
    SetTimer(SummaryTick, 0)
    UpdateStartControls()
    HudLeave()
    mins := Round((A_TickCount - Stats.start) / 60000)
    if (msg != "") {
        SetPhase("error", "Stopped", msg)
        Cue("error")
        LogEvent("Stopped: " msg)
        if was
            Alert("error", "Fishing stopped: " msg, true)
    } else {
        if was
            Alert("stop", Format("Fishing stopped after {} min: {} casts, {} reels.", mins, Stats.casts, Stats.reels))
        SetPhase("idle", "Ready", IdleHint())
        if was
            LogEvent("Stopped")
    }
    SetGauge(0.36, 0.64, 0.5, false)
}

MacroLoop() {
    global LoopActive, CurRod, SovReels, LiveBand, LiveGeo
    LoopActive := true
    UsePhysicalPixels()
    misses := 0, b := 0, geoKey := ""
    try {
        while Running {
            if ReconnectDue() {
                if !Reconnect()
                    break
                continue
            }
            if !WinExist("ahk_id " RobloxHwnd) {
                if Cfg["AutoReconnect"] {
                    FlagDisconnect("The Roblox window closed")
                    continue
                }
                StopMacro("Roblox closed. Reopen Fisch and press " KeyName(Cfg["ToggleKey"]) ".")
                break
            }
            if !WaitForFocus() {
                if ReconnectDue()
                    continue
                break
            }
            cr := ClientRect(RobloxHwnd)
            if !cr {
                SetPhase("pause", "Paused", "Restore the Roblox window to continue.")
                Sleep 300
                continue
            }
            ; Jobs between catches: aquarium, totems, Sovereign recharge.
            if RunDueJobs()
                continue
            a := AreaRect("Reel", cr), geo := VisionGeo(a)
            k := geo.x "," geo.y "," geo.w "," geo.h
            if (k != geoKey)
                b := BandGrab(geo.w, geo.h), geoKey := k
            LiveBand := b, LiveGeo := geo

            if (Cfg["RodReequip"] && misses >= 3) {
                SetPhase("cast", "Re-equipping rod", "Three casts in a row got no bite.")
                misses := 0
                if !ReequipRod() {
                    if ReconnectDue()
                        continue
                    break
                }
            }
            SetPhase("cast", "Casting", "Holding the cast for " Cfg["CastHold"] " ms.")
            if !Cast() {
                if ReconnectDue()
                    continue
                break
            }
            Stats.casts++
            UpdateStats()
            if !Nap(Cfg["BobberWait"])
                break

            ; Remember the reel row before any bite, so the reel UI can be told
            ; apart from scenery that happens to share its colours.
            VisionGrab(b, geo)
            base := ColsCopy(b)
            SetPhase("wait", "Waiting for a bite")
            found := ShakeUntilReel(b, geo, base)
            if !IsObject(found) {
                if (found = "stop") {
                    if ReconnectDue()
                        continue
                    break
                }
                misses++
                Stats.misses++
                LogEvent("No bite, recasting")
                continue
            }
            misses := 0
            CurRod := found.prof
            SetPhase("reel", "Reeling", "Rod: " found.prof.name)
            MouseToCenter()
            res := Reel(b, geo, base, found)
            ; A reel that ended early (lost tracking) while its UI is still up
            ; is resumed rather than cast over.
            resumes := 0
            while (Running && !res.phantom && resumes < 3 && ReelStillUp(b, geo, found.prof)) {
                resumes++
                LogVision("Reel still up after tracking dropped; resuming")
                res := Reel(b, geo, base, {prof: found.prof, d: 0})
            }
            if !Running
                break
            if ReconnectDue()          ; the game dropped mid-reel: don't count it
                continue
            Stats.reels++
            SovReels++
            UpdateStats()
            SetGauge(0.36, 0.64, 0.5, false)
            if res.phantom
                LogEvent("Reel ended early: the bar stopped answering the mouse")
            else
                LogEvent(Format("Reel done in {:.1f} s, fish centered {}", res.dur / 1000, res.centeredTxt))
            Cue("catch")
            SetPhase("cast", "Reel finished", "Casting again shortly.")
            if !Nap(Cfg["CatchDelay"])
                break
        }
    } catch as err {
        StopMacro("Something went wrong: " err.Message)
    } finally {
        ReleaseMouse()
        LoopActive := false
    }
}

; Runs whichever between-catch job is due. True when one ran.
RunDueJobs() {
    if (Cfg["AqAuto"] && A_TickCount >= AqNext) {
        RunAquarium(false)
        return true
    }
    if TotemDue() {
        RunTotems()
        return true
    }
    if SovereignDue() {
        RunSovereign()
        return true
    }
    return false
}

Cast() {
    if !WaitForFocus()
        return false
    MouseToCenter()
    Sleep 30
    Click("Down")
    ok := Nap(Cfg["CastHold"])
    Click("Up")
    return ok
}

ReequipRod() {
    key := "{" Cfg["RodKey"] "}"
    Send key
    if !Nap(500)
        return false
    Send key
    return Nap(800)
}

; Presses Enter (Navigation mode) or clicks the shake button (Click mode)
; until a reel UI shows up or the bite timer runs out.
; Shakes until the reel shows up, then works out which look it is: a known
; look, a rod with its own reel colours, or (once the track outline is
; visible) a new look learned on the spot.
ShakeUntilReel(b, geo, base) {
    deadline := A_TickCount + Cfg["BiteTimeout"] * 1000
    nav := (Cfg["ShakeMode"] = "Navigation")
    navOn := false
    if (nav && Cfg["UseNavKey"]) {
        Send "{" Cfg["NavKey"] "}"
        navOn := true
    }
    hits := 0, lastShake := 0, lastNote := 0, lastLearn := 0, why := ""
    while Running {
        if (!WaitForFocus() || ReconnectDue())
            return "stop"
        VisionGrab(b, geo)
        r := 0
        if (RowDiff(b, base) > 0.25) {
            r := MatchPrecoded(b, geo)
            if (!r && A_TickCount - lastLearn > 4000) {
                lastLearn := A_TickCount
                LogVision("No built-in reel style fits this reel" (CurRodName != "" ? " (" CurRodName ")" : ""))
            }
        }
        if r {
            if (++hits >= 2) {
                if navOn
                    Send "{" Cfg["NavKey"] "}"
                return r
            }
        } else {
            hits := 0
        }
        now := A_TickCount
        if (now >= deadline) {
            if navOn
                Send "{" Cfg["NavKey"] "}"
            return "timeout"
        }
        if (now - lastShake >= Cfg["ShakeInterval"]) {
            lastShake := now
            if nav
                Send "{Enter}"
            else
                ClickShake()
        }
        if (now - lastNote >= 500) {
            lastNote := now
            SetDetail("Recasting in " Ceil((deadline - now) / 1000) " s if nothing bites.")
        }
        Sleep 3
    }
    return "stop"
}

; Checks one stretch of constant input: the bar must accelerate the way the
; mouse says. Four long stretches in a row failing means the "bar" is
; scenery that happens to share the look's colours.
SegmentAnswers(ts, xs, held, est, okList) {
    n := ts.Length
    if (n < 8 || ts[n] - ts[1] < 90)
        return true
    acc := QuadAccel(ts, xs)
    if (acc = "")
        return true
    ok := held ? acc > 0.25 * est.aH : acc < -0.25 * est.aR
    okList.Push(ok)
    if (okList.Length > 4)
        okList.RemoveAt(1)
    if (okList.Length < 4)
        return true
    for v in okList
        if v
            return true
    return false
}

; Fraction of columns whose colour changed from the reference row.
RowDiff(b, base) {
    n := 0, cols := b.cols
    Loop b.w {
        o := (A_Index - 1) * 4
        if (ColDist(NumGet(cols, o, "UInt"), NumGet(base, o, "UInt")) > 28)
            n++
    }
    return n / b.w
}

ColsCopy(b) {
    c := Buffer(b.w * 4)
    DllCall("RtlMoveMemory", "Ptr", c, "Ptr", b.cols, "UPtr", b.w * 4)
    return c
}

; After a reel ends, is it actually still up? Two of three looks must show
; it: the track outline where this look's outline sits, or the bar in this
; look's colours with the outline not contradicting it.
ReelStillUp(b, geo, p) {
    hits := 0
    Loop 3 {
        VisionGrab(b, geo)
        d := VisionScan(b, p)
        ep := EdgesPresent(b, geo, p)
        hits += (ep = 1) || (d.bar && d.cover >= 0.8 && ep != 0)
        Sleep 40
    }
    return hits >= 2
}

LogVision(msg) {
    VisionLog.InsertAt(1, FormatTime(, "HH:mm:ss") "  " msg)
    if (VisionLog.Length > 40)
        VisionLog.Pop()
    try LiveLogChanged()
}

ClickShake() {
    cr := ClientRect(RobloxHwnd)
    if !cr
        return
    s := AreaRect("Shake", cr)
    if PixelSearch(&x, &y, s.x1, s.y1, s.x2, s.y2, 0xFFFFFF, Cfg["ShakeTol"]) {
        MouseMove(x + 3, y + 3, 0)
        Sleep 8
        MouseMove(1, 0, 0, "R")
        Click()
    }
}

;------------------------------------------------------------------------------
; Reel control. Holding the mouse accelerates the bar right, releasing lets it
; fall left. The physics style measures those accelerations for each rod and
; brakes on a time-optimal switching curve, so the bar stops with the fish on
; its centre line instead of sliding past it.
;------------------------------------------------------------------------------
Reel(b, geo, base, r) {
    global CurRod, LiveD, LiveP, LiveEp, LiveT, LiveRate
    p := r.prof, w := b.w
    edge := w * Cfg["EdgeMargin"] / 100
    physics := (Cfg["ControlStyle"] = "physics")
    autoLag := physics && Cfg["Latency"] = 0
    L := autoLag ? (Cfg["LearnedLag"] > 0 ? Cfg["LearnedLag"] : 40) : Cfg["Latency"]
    brk := Cfg["Braking"] / 100, look := Cfg["Predict"], lead := Cfg["FishLead"] / 100
    est := {aH: 3.0 * w / 1e6, aR: 3.0 * w / 1e6, wH: 0.2, wR: 0.2, nH: 0, nR: 0, fits: 0}
    lag := LagEstimator(L)
    holding := false, tSwitch := QPC() - 1000, sw := [[tSwitch, false]]
    c := -1, v := 0, tC := 0, f := -1, fv := 0, tF := 0
    lastBl := -2, lastBr := -2, lastFx := -2, tFrame := 0, vmaxSeen := 0
    widths := [], bw := 0, memKey := "", segT := [], segX := []
    t0 := A_TickCount, lastUI := t0, lastDash := 0, frame := 0, ep := -1, good := 0
    lostSince := 0, lastRelearn := 0, phantom := false, why := "", segOK := [], still := [], gone := 0, stale := 0, sawEdges := false
    trail := [], lostHbm := 0, lostAt := -1, wasPresent := false, endWhy := "", snaps := Cfg["ReelSnaps"]
    d := (r.HasOwnProp("d") && IsObject(r.d)) ? r.d : 0
    nIn := 0, nCtr := 0, errSum := 0, nBoth := 0, rateT := A_TickCount, rateF := 0
    SetGauge(0.36, 0.64, 0.5, true)
    while Running {
        if !WinActive("ahk_id " RobloxHwnd) {
            if holding {
                Click("Up")
                holding := false, tSwitch := QPC(), sw.Push([tSwitch, false])
            }
            if !WaitForFocus()
                break
            lastUI := A_TickCount
            continue
        }
        if (frame > 0 || !IsObject(d)) {
            VisionGrab(b, geo)
            d := VisionScan(b, p, f)
            ; Verdant Oath: aim the fish at the green zone, not the bar's centre
            if (p.greenBar && d.bar && d.fish && (gz := GreenZone(b, d)) >= 0)
                d.fx -= gz - (d.bl + d.br) / 2
        }
        frame++
        if (Mod(frame, 4) = 1)
            ep := EdgesPresent(b, geo, p)
        now := A_TickCount
        LiveD := d, LiveP := p, LiveEp := ep, LiveT := now     ; for the Live tab
        if (now - rateT >= 1000)
            LiveRate := frame - rateF, rateT := now, rateF := frame
        ; A block of bar colour at the wrong width is scenery, not the bar.
        if (d.bar && bw && Abs(d.br - d.bl + 1 - bw) > Max(6, bw * 0.35))
            d.bar := false
        ; The reel is up while its track outline shows (once learned), or
        ; while the row fits this look's colours. Strong colour evidence
        ; counts while the outline has never matched in this reel: a window
        ; resize or a new reel area leaves a look's stored outline in the
        ; wrong place, and without this the reel would look gone from its
        ; first frame. Once the outline has matched, it decides again, so
        ; leftover scenery after the catch can't hold the reel open.
        if (ep = 1)
            sawEdges := true
        present := (ep = 1) || (ep = -1 && d.cover >= 0.6) || (!sawEdges && ep = 0 && d.bar && d.cover >= 0.85)
        ; What the macro saw this frame, for the reel-end record.
        if snaps {
            trail.Push(Format("{:6d}  outline {:2d}  fit {:.2f}  bar {} {}-{}  fish {} {}  present {}  held {}"
                , now - t0, ep, d.cover, d.bar ? 1 : 0, d.bl, d.br, d.fish ? 1 : 0, Round(d.fx), present ? 1 : 0, holding ? 1 : 0))
            if (trail.Length > 150)
                trail.RemoveAt(1)
            if (wasPresent && !present) {
                if lostHbm
                    DllCall("DeleteObject", "Ptr", lostHbm)
                lostHbm := BandCopy(b), lostAt := now - t0
            }
            wasPresent := present
        }
        ; The outline alone keeps the reel alive: the bar or fish can change
        ; look for a moment (a flash, a glow, the fish on the bar).
        if (present && (d.fish || d.bar || ep = 1)) {
            lastUI := now, good++
            if (good = 30 && p.edgeT = "") {
                e := FindEdges(b, geo)
                if e.ok
                    RememberEdges(p, e, geo), ep := 1
            }
            ; The outline keeps missing while the colours say otherwise:
            ; it was learned somewhere else, so drop it and learn it again.
            stale := (ep = 0) ? stale + 1 : 0
            if (stale = 12) {
                p.edgeT := "", p.edgeB := "", ep := -1, good := 0
                LogVision("Reel outline no longer matched, learning it again")
            }
        }
        if (now - lastUI > 450 || now - t0 > 120000) {
            endWhy := now - t0 > 120000 ? "two-minute limit" : "the reel looked gone for 450 ms"
            break
        }
        ; The moment the reel looks gone, let go and press nothing: in Fisch a
        ; press-and-release after the catch casts the rod again.
        if (!present || !(d.bar || d.fish)) {
            gone++
            if (!present || gone >= 2) {
                if holding
                    Click("Up"), holding := false, tSwitch := QPC(), sw.Push([tSwitch, false]), segT := [], segX := []
                FineSleep(Cfg["ScanDelay"])
                continue
            }
        } else {
            gone := 0
        }
        tq := QPC()
        ; Roblox redraws about 60 times a second while this loop scans faster.
        ; Only a changed picture counts as a new measurement.
        fresh := (d.bl != lastBl || d.br != lastBr || d.fx != lastFx || tq - tFrame >= 25)
        if fresh
            lastBl := d.bl, lastBr := d.br, lastFx := d.fx, tFrame := tq
        while (sw.Length > 2 && sw[2][1] < tq - 450)
            sw.RemoveAt(1)

        ; Bar centre: a tracker that predicts with the learned physics and the
        ; inputs already sent, then corrects toward the measurement.
        if (d.bar && fresh) {
            cm := (d.bl + d.br) / 2
            if (c < 0) {
                c := cm, v := 0
            } else {
                dt := Max(1, tq - tC)
                AccelOver(sw, tC, tq, L, est.aH, est.aR, &dv, &dx)
                cp := c + v * dt + dx
                res := cm - cp
                c := cp + 0.5 * res
                v := v + dv + 0.2 * res / Max(dt, 8)
            }
            tC := tq
            vmaxSeen := Max(vmaxSeen, Abs(v))
            nearWall := d.bl <= 2 || d.br >= w - 3
            if (widths.Length < 40)
                widths.Push(d.br - d.bl + 1)
            if autoLag {
                lag.Observe(sw, tq, cm, c, v, est.aH, est.aR, w, (d.br - d.bl) / 2, vmaxSeen)
                L := lag.value
            }
            ; Samples for the acceleration fit: away from the walls, after the
            ; latest input change has taken effect, and (with Auto latency) only
            ; once the delay has been measured, since a wrong delay skews the fit.
            tau := tq - tSwitch - L
            if (tau >= 8 && !nearWall) {
                segT.Push(tau), segX.Push(cm)
                if (segT.Length >= 6 && segT[segT.Length] - segT[1] >= 250) {
                    ; The scenery guard only acts while the track outline isn't
                    ; confirming the reel: the outline exists only on the real
                    ; reel UI, and input lag or a rod's odd physics can make a
                    ; real bar look like it isn't answering.
                    if (!SegmentAnswers(segT, segX, holding, est, segOK) && ep != 1)
                        phantom := true
                    if (physics && (!autoLag || lag.n >= 40))
                        FitSegment(segT, segX, holding, est, w)
                    else
                        segT.Length := 0, segX.Length := 0
                }
            }
            ; A real bar can't sit still for a second while the mouse has been
            ; held or released for a long stretch; scenery can.
            still.Push([tq, cm])
            while (still.Length > 2 && still[2][1] < tq - 1200)
                still.RemoveAt(1)
            if (!nearWall && tq - still[1][1] >= 1100 && tq - tSwitch >= 150) {
                lo := 1e9, hi := -1e9
                for s in still
                    lo := Min(lo, s[2]), hi := Max(hi, s[2])
                if (hi - lo < 3 && ep != 1)
                    phantom := true
            }
            if phantom
                break
        } else if (c >= 0 && tq - tC > 300) {
            v := 0
        }

        ; Once the bar width settles, load what was learned about this rod.
        if (memKey = "" && widths.Length >= 12) {
            bw := MedianOf(widths)
            memKey := p.id "@" Round(100 * bw / w)
            if RodMem.Has(memKey) {
                m := RodMem[memKey]
                est.aH := m.aH * w / 1e6, est.aR := m.aR * w / 1e6
                est.wH := est.wR := Min(m.n, 5) * 40
                est.nH := est.nR := Min(m.n, 3)
            }
            UpdateRodInfo(p, bw / w, memKey)
        }

        ; Fish: same kind of tracker, used to lead the target.
        if (d.fish && fresh) {
            if (f < 0) {
                f := d.fx, fv := 0
            } else {
                dt := Max(1, tq - tF)
                fp := f + fv * dt
                res := d.fx - fp
                f := fp + 0.6 * res
                fv := Clamp(fv + 0.15 * res / Max(dt, 8), -3, 3)
            }
            tF := tq
        }

        haveFish := d.fish || (f >= 0 && tq - tF < 300)
        if !haveFish {
            hold := v < 0                          ; hover in place
        } else {
            fx := d.fish ? f : f + fv * (tq - tF)
            if (fx <= edge)
                hold := false
            else if (fx >= w - edge)
                hold := true
            else if (c < 0)
                hold := fx > w / 2
            else if physics {
                ; Where the bar will be when an input sent now takes effect,
                ; counting the inputs that are still on their way.
                AccelOver(sw, tC, tq + L, L, est.aH, est.aR, &dv, &dx)
                cL := c + v * (tq + L - tC) + dx, vL := v + dv
                hw := bw ? bw / 2 : w * 0.1
                if (cL < hw)
                    cL := hw, vL := Max(0, vL)
                else if (cL > w - hw)
                    cL := w - hw, vL := Min(0, vL)
                eL := (f + lead * fv * (tq + L - tF)) - cL     ; fish relative to bar centre
                de := lead * fv - vL
                ab := de > 0 ? est.aH : est.aR                ; braking acceleration available
                hold := (eL + brk * de * Abs(de) / (2 * ab)) > 0
            } else {
                hold := fx > c + v * (tq - tC) + v * look
            }
        }
        ; Roblox reads input once per frame, so never flip faster than that.
        if (hold != holding && tq - tSwitch >= 16) {
            if (!SegmentAnswers(segT, segX, holding, est, segOK) && ep != 1) {
                phantom := true
                break
            }
            if (physics && (!autoLag || lag.n >= 40))
                FitSegment(segT, segX, holding, est, w)
            segT := [], segX := []
            Click(hold ? "Down" : "Up")
            holding := hold, tSwitch := tq
            sw.Push([tq, hold])
        }

        if (d.fish && d.bar) {
            half := Max(1, (d.br - d.bl) / 2)
            e := Abs(d.fx - (d.bl + d.br) / 2) / half
            nBoth++, errSum += Min(e, 2)
            nIn += (e <= 1), nCtr += (e <= 0.35)
        }
        if (c >= 0 && now - lastDash >= (Cfg["ReduceMotion"] ? 150 : 45)) {
            lastDash := now
            hw := bw ? bw / 2 : (d.bar ? (d.br - d.bl) / 2 : w * 0.1)
            SetGauge((c - hw) / w, (c + hw) / w, haveFish ? (d.fish ? d.fx : f) / w : -1, true)
            off := (d.fish && d.bar) ? (d.fx - (d.bl + d.br) / 2) / Max(1, (d.br - d.bl) / 2) : ""
            SetLive(off, nBoth ? nCtr / nBoth : "")
        }
        FineSleep(Cfg["ScanDelay"])
    }
    if holding
        Click("Up")
    if (autoLag && lag.n >= 150) {
        Cfg["LearnedLag"] := Round(lag.value)
        Save("LearnedLag")
    }
    if (physics && memKey != "" && est.fits > 0) {
        RememberRod(memKey, est.aH * 1e6 / w, est.aR * 1e6 / w)
        UpdateRodInfo(p, bw / w, memKey)
    }
    if (good >= 30) {
        p.reels++
        if bw
            p.barW := Round(bw / w, 3)
        TouchProfile(p)
    }
    if phantom
        LogVision("Reel ended: the bar stopped answering the mouse (scenery, not the reel)")
    if snaps {
        try SaveReelSnapshot(b, geo, p, trail, lostHbm, lostAt
            , phantom ? "the bar stopped answering the mouse (treated as scenery)" : endWhy != "" ? endWhy : "stopped"
            , A_TickCount - t0, good)
        if lostHbm
            DllCall("DeleteObject", "Ptr", lostHbm)
    }
    return {dur: A_TickCount - t0, frames: nBoth, inside: nBoth ? nIn / nBoth : 0, phantom: phantom, good: good
        , centered: nBoth ? nCtr / nBoth : 0, err: nBoth ? errSum / nBoth : 0, rod: p
        , lag: autoLag ? lag.value : L, lagN: lag.n, loops: frame
        , centeredTxt: nBoth ? Round(100 * nCtr / nBoth) "% of the time" : "n/a"}
}

; Integrates the bar's acceleration over [t1, t2] when each input change
; takes effect `lag` ms after it was sent. sw holds [time, holding] pairs,
; oldest first. Returns the velocity change and the extra displacement
; (beyond constant velocity) reached at t2.
AccelOver(sw, t1, t2, lag, aH, aR, &dv, &dx) {
    dv := 0, dx := 0
    if (t2 <= t1)
        return
    i := sw.Length
    while (i > 1 && sw[i][1] + lag > t1)
        i--
    held := sw[i][2], s := t1, j := i + 1
    loop {
        e := t2
        if (j <= sw.Length && sw[j][1] + lag < t2)
            e := Max(s, sw[j][1] + lag)
        acc := held ? aH : -aR
        dv += acc * (e - s)
        dx += acc * ((t2 - s) ** 2 - (t2 - e) ** 2) / 2
        if (e >= t2)
            return
        held := sw[j][2], s := e, j++
    }
}

; Measures input latency while reeling. For each candidate delay it predicts
; where the bar should be now from where it was about 60 ms ago plus the
; inputs sent since, and keeps a slowly fading squared error. The delay with
; the smallest error, refined between neighbours, wins.
class LagEstimator {
    __New(start) {
        this.cands := [], this.err := [], this.hist := []
        this.n := 0, this.value := start, this.lastObs := 0, this.moved := false
        Loop 21
            this.cands.Push((A_Index - 1) * 10), this.err.Push(0)
    }
    Observe(sw, tq, cm, c, v, aH, aR, w, hw, vmaxSeen) {
        this.hist.Push([tq, c, v])
        while (this.hist.Length > 2 && this.hist[2][1] <= tq - 60)
            this.hist.RemoveAt(1)
        if (tq - this.lastObs < 10)
            return
        s := this.hist[1], H := tq - s[1]
        if (H < 45 || H > 130)
            return
        ; skip moments the model can't explain: walls and top speed
        if (Abs(s[3]) > 0.9 * vmaxSeen || Abs(v) > 0.9 * vmaxSeen)
            return
        if (s[2] - hw < 3 || s[2] + hw > w - 4 || cm - hw < 3 || cm + hw > w - 4)
            return
        this.lastObs := tq
        for k, lk in this.cands {
            AccelOver(sw, s[1], tq, lk, aH, aR, &dv, &dx)
            e := cm - (s[2] + s[3] * H + dx)
            this.err[k] := this.err[k] * 0.996 + e * e
        }
        this.n++
        if (this.n >= 40 && Mod(this.n, 8) = 0) {
            ; The first estimate replaces the stored starting value outright, since
            ; latency can change between sessions; later ones move gradually.
            b := this.Best()
            this.value := this.moved ? Clamp(b, this.value - 20, this.value + 20) : b
            this.moved := true
        }
    }
    Best() {
        bi := 1
        for k, e in this.err
            if (e < this.err[bi])
                bi := k
        best := this.cands[bi]
        if (bi > 1 && bi < this.cands.Length) {
            e0 := this.err[bi - 1], e1 := this.err[bi], e2 := this.err[bi + 1]
            den := e0 - 2 * e1 + e2
            if (den > 0)
                best += 10 * Clamp(0.5 * (e0 - e2) / den, -0.5, 0.5)
        }
        return best
    }
}

; Folds one constant-input stretch of bar motion into the acceleration
; estimates. A fitted curvature's error shrinks with the square of the
; stretch's length, so each stretch counts samples x duration^4; old evidence
; fades so a changed rod is relearned quickly. After a few fits, values more
; than 3x away from the estimate are treated as glitches.
FitSegment(ts, xs, held, est, w) {
    n := ts.Length
    if (n >= 6 && ts[n] - ts[1] >= 50) {
        T := ts[n] - ts[1]
        acc := QuadAccel(ts, xs)
        if (acc != "") {
            acc := held ? acc : -acc
            cur := held ? est.aH : est.aR, cnt := held ? est.nH : est.nR
            lo := cnt >= 3 ? cur / 3 : 0.2 * w / 1e6
            hi := cnt >= 3 ? cur * 3 : 40 * w / 1e6
            if (acc >= lo && acc <= hi) {
                wt := n * (T / 100) ** 4
                if held {
                    W := est.wH * 0.97
                    est.aH := (W * cur + wt * acc) / (W + wt), est.wH := W + wt, est.nH++
                } else {
                    W := est.wR * 0.97
                    est.aR := (W * cur + wt * acc) / (W + wt), est.wR := W + wt, est.nR++
                }
                est.fits++
            }
        }
    }
    ts.Length := 0, xs.Length := 0
}

QuadAccel(ts, xs) {
    n := ts.Length, mean := 0
    for t in ts
        mean += t
    mean /= n
    s1 := 0, s2 := 0, s3 := 0, s4 := 0, y0 := 0, y1 := 0, y2 := 0
    Loop n {
        t := ts[A_Index] - mean, x := xs[A_Index], t2 := t * t
        s1 += t, s2 += t2, s3 += t2 * t, s4 += t2 * t2
        y0 += x, y1 += x * t, y2 += x * t2
    }
    det := n * (s2 * s4 - s3 * s3) - s1 * (s1 * s4 - s3 * s2) + s2 * (s1 * s3 - s2 * s2)
    if (Abs(det) < 1e-6)
        return ""
    det2 := n * (s2 * y2 - y1 * s3) - s1 * (s1 * y2 - y1 * s2) + y0 * (s1 * s3 - s2 * s2)
    return 2 * det2 / det
}

; AutoHotkey's Sleep rounds up to 10-16 ms. The reel loop needs finer
; timing, so it sleeps through Windows (1 ms timer resolution is set at
; startup), then handles waiting messages so hotkeys and the window stay live.
FineSleep(ms) {
    if (ms > 0)
        DllCall("Sleep", "UInt", ms)
    Sleep -1
}

WaitForFocus() {
    if WinActive("ahk_id " RobloxHwnd)
        return true
    ReleaseMouse()
    saved := {kind: Phase.kind, title: Phase.title, detail: Phase.detail}
    SetPhase("pause", "Paused", "Click into Roblox to continue, or press " KeyName(Cfg["ToggleKey"]) " to stop.")
    while Running {
        if !WinExist("ahk_id " RobloxHwnd) {
            ; With auto-reconnect on, a vanished window is a disconnect to
            ; recover from, not a reason to stop.
            if Cfg["AutoReconnect"] {
                FlagDisconnect("The Roblox window closed")
                SetPhase(saved.kind, saved.title, saved.detail)
                return false
            }
            StopMacro("Roblox closed. Reopen Fisch and press " KeyName(Cfg["ToggleKey"]) ".")
            return false
        }
        if WinActive("ahk_id " RobloxHwnd) {
            SetPhase(saved.kind, saved.title, saved.detail)
            return Nap(300)
        }
        Sleep 150
    }
    return false
}

Nap(ms) {
    finish := A_TickCount + ms
    while (Running && A_TickCount < finish)
        Sleep Min(20, Max(1, finish - A_TickCount))
    return Running
}

MouseToCenter() {
    if (cr := ClientRect(RobloxHwnd))
        MouseMove(cr.x + cr.w // 2, cr.y + cr.h // 2, 0)
}

ReleaseMouse() {
    if GetKeyState("LButton")
        Click("Up")
}

;==============================================================================
; Screen reading
;==============================================================================
FindRoblox() {
    for crit in ["ahk_exe RobloxPlayerBeta.exe", "Roblox ahk_class WINDOWSCLIENT"]
        if (hwnd := WinExist(crit))
            return hwnd
    return 0
}

ClientRect(hwnd) {
    try WinGetClientPos(&x, &y, &w, &h, "ahk_id " hwnd)
    catch
        return 0
    if (w < 200 || h < 150)
        return 0
    return {x: x, y: y, w: w, h: h}
}

AreaRect(name, cr) {
    x1 := cr.x + Round(Cfg[name "X1"] * cr.w), y1 := cr.y + Round(Cfg[name "Y1"] * cr.h)
    x2 := cr.x + Round(Cfg[name "X2"] * cr.w), y2 := cr.y + Round(Cfg[name "Y2"] * cr.h)
    return {x1: x1, y1: y1, x2: x2, y2: y2, w: Max(8, x2 - x1), h: Max(1, y2 - y1), midY: (y1 + y2) // 2}
}

; One screen row captured into memory, scanned in a single pass.


; Tries each known rod signature on the captured row; learns an unknown one.


; Fish marker = the longest narrow run of fish colour. Bar = the outermost bar
; pixels, or the longest bar-coloured run when the outermost ones are implausible.

; Unknown rod: take the most common colour on the row as the track, the
; longest run of anything else as the bar, and a narrow run that is neither
; track nor bar colour as the fish. Returns a compiled profile or 0.

; Most common colour (5 bits per channel) between two pixel indexes.

; Fraction of the row that differs clearly from the pre-bite snapshot.

QPC() {
    static freq := 0
    if !freq
        DllCall("QueryPerformanceFrequency", "Int64*", &freq)
    DllCall("QueryPerformanceCounter", "Int64*", &now := 0)
    return now * 1000 / freq
}

MedianOf(arr) {
    s := []
    for v in arr
        s.Push(v)
    n := s.Length
    Loop n - 1 {
        i := A_Index + 1, v := s[i], j := i - 1
        while (j >= 1 && s[j] > v)
            s[j + 1] := s[j], j--
        s[j + 1] := v
    }
    return n ? s[(n + 1) // 2] : 0
}

PanelCoversReel(hwnd) {
    cr := ClientRect(hwnd)
    if (!cr || !IsObject(MainGui))
        return false
    try {
        if (WinGetMinMax("ahk_id " MainGui.Hwnd) = -1)
            return false
        WinGetPos(&x, &y, &w, &h, "ahk_id " MainGui.Hwnd)
    } catch {
        return false
    }
    a := AreaRect("Reel", cr)
    return !(x >= a.x2 || x + w <= a.x1 || y >= a.midY + 1 || y + h <= a.midY)
}

UsePhysicalPixels() {
    try DllCall("SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")
}


;==============================================================================
; Auto aquarium. Opens Fisch's aquarium panel, scrolls through the fish food
; cards, presses Use on food you own and Buy on shop cards up to the limit,
; then uses what it bought. Food buttons are rectangles outlined in bright
; green; Buy buttons are a purer green than Use buttons.
;==============================================================================
RunAquariumNow() {
    SetTimer(() => RunAquarium(true), -1)
}

RunAquarium(manual := false) {
    global AqNext, AqManual, AqAbort, AqLast, RobloxHwnd
    if manual {
        if (Running || Calibrating || AqManual)
            return
        UsePhysicalPixels()
        h := FindRoblox()
        if !h {
            SetPhase("error", "Roblox isn't open", "Open Fisch first, then run the aquarium.")
            Cue("error")
            return
        }
        RobloxHwnd := h
        AqManual := true, AqAbort := false
        UpdateStartControls()
        try WinActivate("ahk_id " h)
        Sleep 350
    }
    result := ""
    try {
        result := AquariumVisit()
    } catch as err {
        result := "failed: " err.Message
    }
    AqNext := A_TickCount + Cfg["AqEvery"] * 60000
    AqLast := result
    LogEvent("Aquarium " result)
    Alert("aquarium", "Aquarium " result ".")
    if manual {
        AqManual := false
        UpdateStartControls()
        if InStr(result, "failed")
            SetPhase("error", "Aquarium visit failed", SubStr(result, 9))
        else
            SetPhase("idle", "Aquarium visit done", StrTitle(SubStr(result, 1, 1)) SubStr(result, 2) ".")
    }
    RefreshRobloxInfo()
    return result
}

AqAlive() => (Running || AqManual) && !AqAbort

AquariumVisit() {
    SetPhase("aqua", "Tending the aquarium", "Opening the aquarium panel.")
    cr := ClientRect(RobloxHwnd)
    if !cr
        return "failed: the Roblox window isn't ready"
    MouseGetPos(&mx, &my)
    ReleaseMouse()
    aq := AqContext(cr)
    if !AqPanelSure(aq) {
        AqTap(aq.navX, aq.navY)
        AqWaitPanel(aq, true)
    }
    if (!AqPanelSure(aq) && AqAlive())
        AqRecoverRow(aq)
    if !AqPanelSure(aq) {
        MouseMove(mx, my, 0)
        return AqAlive() ? "failed: couldn't find the fish food panel" : "stopped"
    }
    aq.pitch := AqMeasurePitch(aq)
    SetDetail("Using fish food.")
    AqSweep(aq, false)
    if (aq.buys > 0 && AqAlive()) {
        SetDetail("Using the food it just bought.")
        AqSweep(aq, true)
    }
    AqScrollHome(aq)
    if AqPanelSure(aq) {
        SetDetail("Closing the aquarium panel.")
        AqTap(aq.navX, aq.navY)
        AqWaitPanel(aq, false)
    }
    MouseMove(mx, my, 0)
    if !AqAlive() && !aq.uses && !aq.buys
        return "stopped"
    return Format("used {}, bought {}", aq.uses, aq.buys)
}

AqContext(cr) {
    k := Clamp(cr.h / 1080, 0.5, 3)
    x0 := cr.x + Round(cr.w * 0.04), y0 := cr.y + Round(cr.h * 0.33)
    w := Round(cr.w * 0.92), h := Round(cr.h * 0.65)
    return {cr: cr, k: k, x0: x0, y0: y0, g: AreaGrab(w, h), btns: [], hoverX: 0, hoverY: 0, hoverOk: false
        , navX: UiSpot("aquariums", cr).x, navY: UiSpot("aquariums", cr).y
        , pitch: 0, uses: 0, buys: 0, done: 0}
}

class AreaGrab {
    __New(w, h) {
        this.w := w := Max(1, w), this.h := h := Max(1, h)
        bi := Buffer(40, 0)
        NumPut("UInt", 40, bi, 0), NumPut("Int", w, bi, 4), NumPut("Int", -h, bi, 8)
        NumPut("UShort", 1, bi, 12), NumPut("UShort", 32, bi, 14)
        this.dc := DllCall("CreateCompatibleDC", "Ptr", 0, "Ptr")
        this.bmp := DllCall("CreateDIBSection", "Ptr", this.dc, "Ptr", bi, "UInt", 0, "Ptr*", &bits := 0, "Ptr", 0, "UInt", 0, "Ptr")
        this.bits := bits
        this.old := DllCall("SelectObject", "Ptr", this.dc, "Ptr", this.bmp, "Ptr")
    }
    Grab(x, y) {
        sdc := DllCall("GetDC", "Ptr", 0, "Ptr")
        DllCall("BitBlt", "Ptr", this.dc, "Int", 0, "Int", 0, "Int", this.w, "Int", this.h
            , "Ptr", sdc, "Int", x, "Int", y, "UInt", 0x00CC0020)
        DllCall("ReleaseDC", "Ptr", 0, "Ptr", sdc)
    }
    __Delete() {
        DllCall("SelectObject", "Ptr", this.dc, "Ptr", this.old)
        DllCall("DeleteObject", "Ptr", this.bmp)
        DllCall("DeleteDC", "Ptr", this.dc)
    }
}

AqScan(aq) {
    aq.g.Grab(aq.x0, aq.y0)
    n := AqFindButtons(aq)
    if n {
        aq.hoverX := aq.btns[1].x, aq.hoverY := aq.btns[1].y, aq.hoverOk := true
    }
    return n
}

; Green edge pixel: G at least 240 and B between 100 and 160.
AqFindButtons(aq) {
    g := aq.g, pb := g.bits, W := g.w, H := g.h, k := aq.k
    minW := Round(55 * k), maxW := Round(W * 0.45), minH := Round(16 * k), maxH := Round(96 * k)
    tol := Max(3, Round(6 * k)), stepX := Max(4, Round(8 * k))
    lines := [], prev := -99, y := 0
    while (y < H) {
        off := y * W * 4, hits := 0, x := 0
        while (x < W) {
            c := NumGet(pb, off + x * 4, "UInt")
            if (((c >> 8) & 255) >= 240 && (c & 255) >= 100 && (c & 255) <= 160) {
                hits++
                if (hits >= 6)
                    break
            }
            x += stepX
        }
        if (hits >= 6) {
            if (y - prev > 2)
                lines.Push(y)
            prev := y
        }
        y++
    }
    cache := Map(), seen := Map(), btns := []
    for ia, ya in lines {
        ra := AqRuns(pb, W, ya, minW, cache)
        ib := ia + 1
        while (ib <= lines.Length) {
            yb := lines[ib], ib++
            gap := yb - ya
            if (gap < minH)
                continue
            if (gap > maxH)
                break
            rb := AqRuns(pb, W, yb, minW, cache)
            for sa in ra {
                if (sa[2] - sa[1] > maxW)
                    continue
                for sb in rb {
                    if (Abs(sa[1] - sb[1]) > tol || Abs(sa[2] - sb[2]) > tol)
                        continue
                    key := ((sa[1] + sa[2]) // 2) "_" ya
                    if seen.Has(key)
                        continue
                    seen[key] := 1
                    if (b := AqMakeButton(aq, pb, W, sa, ya, yb))
                        btns.Push(b)
                }
            }
        }
    }
    ; left to right
    n := btns.Length
    Loop n - 1 {
        i := A_Index + 1, b := btns[i], j := i - 1
        while (j >= 1 && btns[j].x > b.x)
            btns[j + 1] := btns[j], j--
        btns[j + 1] := b
    }
    aq.btns := btns
    return n
}

AqRuns(pb, W, y, minW, cache) {
    if cache.Has(y)
        return cache[y]
    runs := [], rs := -1, off := y * W * 4
    Loop W + 1 {
        x := A_Index - 1, on := false
        if (x < W) {
            c := NumGet(pb, off + x * 4, "UInt")
            on := ((c >> 8) & 255) >= 240 && (c & 255) >= 100 && (c & 255) <= 160
        }
        if (on && rs < 0)
            rs := x
        else if (!on && rs >= 0) {
            if (x - rs >= minW)
                runs.Push([rs, x])
            rs := -1
        }
    }
    cache[y] := runs
    return runs
}

AqMakeButton(aq, pb, W, run, ya, yb) {
    sum := 0, n := 0, off := ya * W * 4, x := run[1]
    while (x < run[2]) {
        c := NumGet(pb, off + x * 4, "UInt")
        gg := (c >> 8) & 255, b := c & 255
        if (gg >= 240 && b >= 100 && b <= 160)
            sum += gg - ((c >> 16) & 255), n++
        x++
    }
    if (n < 12)
        return 0
    return {x: aq.x0 + (run[1] + run[2]) // 2, y: aq.y0 + (ya + yb) // 2, kind: (sum / n > 60) ? "buy" : "use"
        , w: run[2] - run[1], h: yb - ya}
}

AqPanelSure(aq) {
    Loop 3 {
        if (AqScan(aq) > 0)
            return true
        if !AqAlive()
            return false
        Sleep 150
    }
    return false
}

AqWaitPanel(aq, want) {
    start := A_TickCount, cap := Cfg["AqOpenWait"] + 3000
    while AqAlive() {
        Sleep 150
        if ((AqScan(aq) > 0) = want)
            return true
        if (A_TickCount - start >= cap)
            return false
    }
    return false
}

AqTap(x, y) {
    MouseMove(x, y, 0)
    Sleep 55
    Click()
}

AqWheel(aq, n, dir) {
    if (!aq.hoverOk && AqScan(aq) < 1)
        return false
    MouseMove(aq.hoverX, aq.hoverY, 0)
    Sleep 60
    Loop n {
        Click(dir > 0 ? "WheelDown" : "WheelUp")
        Sleep 30
    }
    Sleep 130
    return true
}

AqLeftX(aq) => aq.btns.Length ? aq.btns[1].x : -99999

AqScrollHome(aq) {
    last := -99999
    Loop 20 {
        if (!AqAlive() || !AqWheel(aq, Cfg["AqScrollSteps"], -1))
            return false
        AqScan(aq)
        cur := AqLeftX(aq)
        if (aq.btns.Length && cur = last)
            return true
        last := cur
    }
    return true
}

; The row may be scrolled out of view when the panel opens; nudge it back.
AqRecoverRow(aq) {
    aq.hoverX := aq.cr.x + Round(aq.cr.w * 0.5), aq.hoverY := aq.cr.y + Round(aq.cr.h * 0.62), aq.hoverOk := true
    spent := 0
    Loop 6 {
        if !AqWheel(aq, 5, -1)
            break
        spent += 5
        if (AqScan(aq) >= 1)
            return true
    }
    if spent
        AqWheel(aq, spent, 1)
    aq.hoverOk := false
    return false
}

AqMeasurePitch(aq) {
    best := 0
    if (AqScan(aq) >= 2) {
        Loop aq.btns.Length - 1
            best := Max(best, aq.btns[A_Index + 1].x - aq.btns[A_Index].x)
    }
    if (best < 20) {
        wmax := 0
        for b in aq.btns
            wmax := Max(wmax, b.w)
        best := Max(Round(60 * aq.k), Round(wmax * 1.4))
    }
    return best
}

; Walks the card row left to right. Cards are tracked by content position
; (screen x plus how far the row has scrolled) so none is pressed twice.
AqSweep(aq, useOnly) {
    AqScrollHome(aq)
    shift := 0, seenMax := -999999, half := Max(20, aq.pitch // 2), stall := 0, pressed := []
    AqScan(aq)
    Loop 60 {
        if (!AqAlive() || aq.done >= Cfg["AqMaxUses"])
            break
        hitShop := false
        list := []
        for b in aq.btns
            list.Push(b)
        for b in list {
            if (!AqAlive() || aq.done >= Cfg["AqMaxUses"])
                break
            cx := b.x + shift
            if (cx <= seenMax + half || AqNear(pressed, cx, half))
                continue
            seenMax := cx
            if (b.kind = "buy") {
                if useOnly {
                    hitShop := true
                    break
                }
                if (aq.buys >= Cfg["AqMaxBuys"])
                    continue
                aq.buys++
            } else {
                aq.uses++
            }
            aq.done++
            pressed.Push(cx)
            AqTap(b.x, b.y)
            Sleep Cfg["AqStepDelay"]
        }
        if hitShop
            break
        AqScan(aq)
        prevLeft := AqLeftX(aq), oldX := []
        for b in aq.btns
            oldX.Push(b.x)
        if !AqWheel(aq, 1, 1)
            break
        if (AqScan(aq) < 1)
            break
        newX := []
        for b in aq.btns
            newX.Push(b.x)
        shift += AqShiftBetween(oldX, newX, aq.pitch)
        if (AqLeftX(aq) = prevLeft) {
            if (++stall >= 3)
                break
        } else {
            stall := 0
        }
    }
}

; How far the row moved left between two scans. If most buttons sit where
; they were, the row didn't move (the end of the row). Otherwise the median of
; plausible differences. When nothing lines up the answer is 0: an unclear
; scroll can then only cause a skipped card, never a second press.
AqShiftBetween(oldX, newX, pitch) {
    if (!oldX.Length || !newX.Length || pitch < 20)
        return 0
    same := 0
    for nx in newX {
        for ox in oldX {
            if (Abs(ox - nx) <= 2) {
                same++
                break
            }
        }
    }
    if (same * 2 >= newX.Length)
        return 0
    ds := [], hi := Round(pitch * 0.92)
    for ox in oldX
        for nx in newX
            if (ox - nx >= 3 && ox - nx <= hi)
                ds.Push(ox - nx)
    return ds.Length ? MedianOf(ds) : 0
}

AqNear(list, x, tol) {
    for v in list
        if (Abs(v - x) < tol)
            return true
    return false
}

AqInfoText() {
    if !Cfg["AqAuto"]
        return "Off"
    if (AqNext = 0)
        return "Next visit when fishing starts"
    mins := Ceil((AqNext - A_TickCount) / 60000)
    return mins > 0 ? "Next visit in " mins " min" : "Due now"
}

AqTileText() => Cfg["AqAuto"] ? "On, every " Cfg["AqEvery"] " min" : "Off. Feeds fish between catches"

;==============================================================================
; Window. A sidebar of tabs on the left (the basics, or the Advanced set
; behind a toggle), the page on the right in one column, and a slim status
; line along the bottom. While fishing, the window steps aside for a small
; panel in the top-right corner (class Hud). The coloured areas are painted
; in WM_ERASEBKGND, so no control ever sits on top of another.
;==============================================================================
BuildGui() {
    global MainGui, UiReady, UI, Clickables, Pages, FocusGlobal, DescOf, EditCtls
    global Steppers, Toggles, KeyBtns, SegCtls, Swatches, Choices, FocusIdx, FocusOn, Hover, ColX, RowBase
    UiReady := false
    UI := {tabs: Map(), navRows: Map(), navMode: "basic", menuBtns: Map(), units: Map(), sbLeft: [], sbRight: []
        , gX: 0, gW: 100, gLive: -1, phaseColor: "", dash: [], rodRows: [], totemRows: [], liveVals: Map(), hiddenForHud: false}
    Clickables := Map(), Pages := Map(), FocusGlobal := [], DescOf := Map(), EditCtls := Map()
    Steppers := Map(), Toggles := Map(), KeyBtns := Map(), SegCtls := Map(), Swatches := Map(), Choices := Map()
    FocusIdx := 0, FocusOn := false, Hover := 0, ColX := PAGE_X - PAD, RowBase := ROW_Y0
    for t in TabNames
        Pages[t] := {ctls: [], focus: [], desc: ""}
    MainGui := Gui("-Caption +MinimizeBox" (Cfg["OnTop"] ? " +AlwaysOnTop" : ""), APP_NAME)
    MainGui.BackColor := Pal.content
    MainGui.MarginX := 0, MainGui.MarginY := 0
    MainGui.OnEvent("Close", (*) => ExitApp())
    BuildSidebar()
    BuildChrome()
    BuildStatusBar()
    BuildHome(), BuildFishing(), BuildTotems(), BuildAquarium(), BuildSovereign(), BuildAlerts(), BuildReconnect(), BuildSettings()
    BuildRods(), BuildLive(), BuildReel(), BuildTiming(), BuildMore()
    ColX := PAGE_X - PAD, RowBase := ROW_Y0
    UI.desc := AddT(0, PAGE_X, 354, LEFT_W, 32, "", "body", 9, Pal.dim, Pal.content)
    UI.ring := []
    Loop 4
        UI.ring.Push(MainGui.Add("Text", "x0 y0 w1 h1 Hidden Background" Pal.focus))
    BuildMenus()
    UiReady := true
    RodsChanged(), TotemsChanged()
}

NavIcon(name) {
    static icons := Map("Home", 0xE80F, "Fishing", 0xE768, "Totems", 0xE706, "Aquarium", 0xE71D, "Sovereign", 0xE945
        , "Alerts", 0xE715, "Reconnect", 0xE72C, "Settings", 0xE713, "Rods", 0xE8B7, "Live", 0xE9D9, "Reel", 0xE7C3
        , "Timing", 0xE823, "More", 0xE712)
    return icons.Has(name) ? icons[name] : 0xE76C
}

; The sidebar: logo, the tabs, and the start button at the bottom.
BuildSidebar() {
    x := 14
    if (src := LogoImage("icon")) {
        UI.logoHbm := GpScaled(src, ZS(24), ZS(24), "0x" Pal.strip)
        if UI.logoHbm
            MainGui.Add("Picture", Format("x{} y{} w{} h{}", ZS(14), ZS(15), ZS(24), ZS(24)), "HBITMAP:*" UI.logoHbm), x := 46
    }
    AddT(0, x, 10, SIDEBAR_W - x - 6, 34, "FISCHXR", "display", 12, Pal.text, Pal.strip, "0x200")
    y := 56
    for i, name in BasicTabs
        NavRow(name, name, y + (i - 1) * NAV_H, "basic")
    UI.navAdv := NavRow("__adv", "Advanced", y + BasicTabs.Length * NAV_H + 6, "basic", 0xE76C)
    UI.navBack := NavRow("__back", "Back", y, "adv", 0xE76B)
    for i, name in AdvTabs
        NavRow(name, name, y + i * NAV_H + 6, "adv")
    UI.startBtn := AddT(0, 12, 364, SIDEBAR_W - 24, 36, "", "body", 10, Pal.ink, Pal.accent, "Center 0x200")
    Clickables[UI.startBtn.Hwnd] := {kind: "btn", fn: (*) => ToggleMacro(), obj: UI.startBtn, bg: Pal.accent, hv: Pal.accentHi}
    FocusGlobal.Push({ctls: [UI.startBtn], name: "Start or stop fishing", act: () => ToggleMacro(), adj: 0, value: 0, desc: ""})
}

; One sidebar entry: an accent mark, an icon and a label side by side.
NavRow(name, label, y, mode, icon := 0) {
    h := NAV_H - 4
    mark := AddT(0, 8, y, 3, h, "", "body", 9, Pal.text, Pal.strip)
    ic := AddT(0, 11, y, 28, h, HasIconFont ? Chr(icon ? icon : NavIcon(name)) : "", HasIconFont ? "icon" : "body", 10, Pal.dim, Pal.strip, "Center 0x200")
    lb := AddT(0, 39, y, SIDEBAR_W - 47, h, label, "body", 10, Pal.dim, Pal.strip, "0x200")
    e := {kind: "tab", name: name, obj: lb, objs: [ic, lb], bg: Pal.strip, hv: Pal.fieldHi}
    Clickables[mark.Hwnd] := e, Clickables[ic.Hwnd] := e, Clickables[lb.Hwnd] := e
    row := {mark: mark, icon: ic, label: lb, mode: mode, entry: e}
    UI.navRows[name] := row
    if (SubStr(name, 1, 2) != "__")
        UI.tabs[name] := lb
    FocusGlobal.Push({ctls: [ic, lb], name: label (SubStr(name, 1, 2) = "__" ? "" : " tab"), act: NavPress.Bind(name), adj: 0, value: 0, desc: "", navMode: mode})
    return row
}

NavPress(name, *) {
    if (name = "__adv")
        return SetNavMode("adv")
    if (name = "__back")
        return SetNavMode("basic")
    SwitchTab(name)
}

; Shows the basic tabs or the Advanced set in the sidebar.
SetNavMode(mode) {
    if (UI.navMode = mode)
        return
    UI.navMode := mode
    PaintTabs()
    Say(mode = "adv" ? "Advanced tabs" : "Basic tabs")
}

BuildChrome() {
    UI.btnMin := ChromeBtn(IconOr(Chr(0xE921), "–"), (*) => MainGui.Minimize())
    UI.btnClose := ChromeBtn(IconOr(Chr(0xE8BB), "×"), (*) => ExitApp(), true)
}

ChromeBtn(text, fn, isClose := false) {
    b := AddRaw(0, 0, 0, ZS(40), ZS(30), text, HasIconFont ? "icon" : "body", HasIconFont ? 9 : 12, Pal.dim, Pal.content, "Center 0x200")
    ; the close button's hover is red, except in the black-and-white theme
    hv := isClose ? (Pal.HasOwnProp("mono") ? "FFFFFF" : "C42B1C") : Pal.field
    hvText := isClose ? (Pal.HasOwnProp("mono") ? "000000" : "FFFFFF") : ""
    Clickables[b.Hwnd] := {kind: "btn", fn: fn, obj: b, bg: Pal.content, hv: hv, hvText: hvText}
    return b
}

BuildStatusBar() {
    UI.sbDot := SbItem(PAGE_X - 4, 14, "●", Pal.dim, "0x200")
    UI.sbStatus := SbItem(PAGE_X + 12, 200, "Ready", Pal.text, "0x200")
    UI.sbCasts := SbItem(212, 70, "Casts 0", Pal.text, "0x200", true)
    UI.sbReels := SbItem(140, 70, "Reels 0", Pal.text, "0x200", true)
    UI.sbTime := SbItem(68, 58, "0:00:00", Pal.text, "0x200", true)
}

SbItem(x, w, text, color, extra, right := false) {
    c := AddT(0, right ? 0 : x, 0, w, STATUS_H, text, "body", 9, color, Pal.bar, extra)
    (right ? UI.sbRight : UI.sbLeft).Push({ctl: c, off: x, dy: 0})
    return c
}

;------------------------------------------------------------------------------
; Pages. One column; the basics on the main tabs, fine-tuning under Advanced.
;------------------------------------------------------------------------------
; Home is the dashboard: what's happening, the fish against the bar, the rod,
; the next job, Roblox, and recent events.
BuildHome() {
    AddT("Home", PAGE_X, 12, LEFT_W - 90, 30, APP_NAME, "display", 15, Pal.text, Pal.content, "0x200")
    UI.hDot := AddT("Home", PAGE_X, 44, 16, 20, "●", "body", 9, Pal.dim, Pal.content, "0x200")
    UI.hRbx := AddT("Home", PAGE_X + 16, 44, LEFT_W - 16, 20, "Looking for Roblox", "body", 9, Pal.dim, Pal.content, "0x200")
    x := PAGE_X, w := LEFT_W
    UI.dStatus := AddT("Home", x, 72, w, 36, "Ready", "display", 18, Pal.text, Pal.content, "0x200")
    UI.dDetail := AddT("Home", x, 108, w, 34, IdleHint(), "body", 9, Pal.dim, Pal.content)
    UI.gFish := AddT("Home", x + 170, 146, 3, 7, "", "body", 9, Pal.text, Pal.faint)
    UI.gL := AddT("Home", x, 155, 10, 12, "", "body", 9, Pal.text, Pal.field)
    UI.gBar := AddT("Home", x + 10, 155, 10, 12, "", "body", 9, Pal.text, Pal.faint)
    UI.gR := AddT("Home", x + 20, 155, 10, 12, "", "body", 9, Pal.text, Pal.field)
    UI.gCtr := AddT("Home", x + 170, 169, 2, 5, "", "body", 9, Pal.text, Pal.faint)
    UI.mOffL := AddT("Home", x, 180, 76, 22, "Fish offset", "body", 9, Pal.dim, Pal.content, "0x200")
    UI.mOff := AddT("Home", x + 76, 180, 60, 22, "–", "num", 11, Pal.text, Pal.content, "0x200")
    UI.mCtrL := AddT("Home", x + w // 2, 180, 66, 22, "Centered", "body", 9, Pal.dim, Pal.content, "0x200")
    UI.mCtr := AddT("Home", x + w // 2 + 66, 180, 60, 22, "–", "num", 11, Pal.text, Pal.content, "0x200")
    UI.sep1 := AddT("Home", x, 208, w, 1, "", "body", 9, Pal.dim, Pal.seam)
    rows := [["lRod", "iRod", "Rod", RodInfoText], ["lPhys", "iPhys", "Reel", "–"], ["lAq", "iAq", "Next job", NextJobText()], ["lRbx", "iRbx", "Roblox", "Checking"]]
    for i, r in rows {
        yy := 214 + (i - 1) * 20
        UI.%r[1]% := AddT("Home", x, yy, 80, 20, r[3], "body", 9, Pal.dim, Pal.content, "0x200")
        UI.%r[2]% := AddT("Home", x + 80, yy, w - 80, 20, r[4], "body", 9, Pal.text, Pal.content, "0x200")
    }
    UI.sep2 := AddT("Home", x, 298, w, 1, "", "body", 9, Pal.dim, Pal.seam)
    UI.evHead := AddT("Home", x, 304, w, 18, "Recent", "body", 9, Pal.dim, Pal.content)
    UI.events := AddT("Home", x, 322, w, 62, EventsText(), "body", 9, Pal.text, Pal.content)
}

BuildFishing() {
    PageHead("Fishing", "Fishing", "Rod key and how the shake is done.")
    KeyBtn("Fishing", 0, "RodKey", "Rod slot key", "The hotbar key for your rod. Totems and recharges also use it to put the rod back.")
    Toggle("Fishing", 1, "RodReequip", "Re-equip after 3 misses", "Presses the rod slot key twice after three casts in a row get no bite, to clear a stuck bobber.")
    Seg("Fishing", 2, "ShakeMode", "Shake method", [["Navigation", "Navigation"], ["Click", "Click"]]
        , "Navigation presses Enter, which needs Fisch's shake mode set to Navigation. Click hunts for the white shake button.")
    ActionBtn("Fishing", 3, "Set reel area", (*) => StartCalibrate("Reel"), "Freeze the screen while a reel bar is up and drag a box just inside the track.")
    ActionBtn("Fishing", 4, "Set shake area", (*) => StartCalibrate("Shake"), "Click mode only: freeze the screen and drag a box where shake buttons pop up.")
    Toggle("Fishing", 5, "ShowAreas", "Show scan areas on Roblox", "Draws the reel and shake areas and the aquarium button's spot on the Roblox window.")
    Pages["Fishing"].desc := "Equip your rod, face the water and press Start."
}

; Scheduled totems (up to six), with the switch that runs them.
BuildTotems() {
    PageHead("Totems", "Totems", "Uses your totems between catches.")
    Toggle("Totems", 0, "TotemAuto", "Use totems while fishing", "Between catches, uses each scheduled totem when it's due, then puts the rod back in hand.")
    Loop TOTEM_MAX {
        i := A_Index, y := RowBase + i * ROW_H, x := PAGE_X
        on := AddT("Totems", x, y, 40, 28, "On", "body", 9, Pal.ink, Pal.accent, "Center 0x200")
        nm := AddT("Totems", x + 46, y, 122, 28, "", "body", 10, Pal.text, Pal.content, "0x200")
        nt := AddT("Totems", x + 170, y, 52, 28, "Night", "body", 9, Pal.dim, Pal.field, "Center 0x200")
        ky := AddT("Totems", x + 228, y, 52, 28, "", "num", 10, Pal.text, Pal.field, "Center 0x200")
        mi := AddT("Totems", x + 288, y, 24, 28, "−", "body", 12, Pal.dim, Pal.field, "Center 0x200")
        ev := AddT("Totems", x + 314, y, 38, 28, "", "num", 10, Pal.text, Pal.field, "Center 0x200")
        pl := AddT("Totems", x + 354, y, 24, 28, "+", "body", 12, Pal.dim, Pal.field, "Center 0x200")
        un := AddT("Totems", x + 382, y, 34, 28, "min", "body", 9, Pal.dim, Pal.content, "0x200")
        dl := AddT("Totems", x + 424, y, 28, 28, "×", "body", 12, Pal.dim, Pal.field, "Center 0x200")
        Clickables[on.Hwnd] := {kind: "tt", op: "on", i: i, obj: on}
        Clickables[nm.Hwnd] := {kind: "tt", op: "name", i: i, obj: nm}
        Clickables[nt.Hwnd] := {kind: "tt", op: "night", i: i, obj: nt}
        Clickables[ky.Hwnd] := {kind: "tt", op: "key", i: i, obj: ky, bg: Pal.field, hv: Pal.fieldHi}
        Clickables[mi.Hwnd] := {kind: "tt", op: "less", i: i, obj: mi, bg: Pal.field, hv: Pal.fieldHi}
        Clickables[pl.Hwnd] := {kind: "tt", op: "more", i: i, obj: pl, bg: Pal.field, hv: Pal.fieldHi}
        Clickables[dl.Hwnd] := {kind: "tt", op: "del", i: i, obj: dl, bg: Pal.field, hv: Pal.fieldHi}
        DescOf[on.Hwnd] := "Turns this totem's schedule on or off."
        DescOf[nm.Hwnd] := "Click to change which totem this is."
        DescOf[nt.Hwnd] := "Night-only totems wait for night, using a scheduled Sundial first."
        DescOf[ky.Hwnd] := "The hotbar key that holds this totem. Click, then press the key."
        for c in [mi, ev, pl, un]
            DescOf[c.Hwnd] := "Minutes between uses."
        DescOf[dl.Hwnd] := "Removes this totem from the schedule."
        AddFocus("Totems", [on, nm], "Totem " i, TotemOp.Bind("on", i), TotemAdj.Bind(i), TotemSpoken.Bind(i), "Space turns it on or off. Arrow keys change the minutes.")
        AddFocus("Totems", [ky], "Totem " i " hotbar key", TotemOp.Bind("key", i), 0, () => "", "Press Enter, then the hotbar key.")
        UI.totemRows.Push({on: on, name: nm, night: nt, key: ky, less: mi, every: ev, more: pl, unit: un, del: dl})
    }
    half := (LEFT_W - 12) // 2
    UI.btnAddTotem := ActionBtn("Totems", 7, "+  Add a totem", (*) => SetTimer(OpenTotemMenu.Bind(0), -1), "Pick a totem to schedule. Aurora and Blue Moon need night.", PAD, half)
    ActionBtn("Totems", 7, "Use totems now", (*) => SetTimer(UseTotemsNow, -1), "Uses every scheduled totem once, right away, so you can check the keys.", PAD + half + 12, half)
    Pages["Totems"].desc := ""
}

BuildAquarium() {
    PageHead("Aquarium", "Aquarium", "Feeds your aquarium between catches.")
    Toggle("Aquarium", 0, "AqAuto", "Auto aquarium", "Between catches, opens the Aquariums tab on a timer, uses your fish food and buys more up to the limit.")
    Stepper("Aquarium", 1, "AqEvery")
    Stepper("Aquarium", 2, "AqMaxUses")
    Stepper("Aquarium", 3, "AqMaxBuys")
    ActionBtn("Aquarium", 4, "Run now", (*) => RunAquariumNow(), "Runs one visit right away so you can watch it work. Press your start key to stop it.")
    Pages["Aquarium"].desc := ""
}

BuildSovereign() {
    PageHead("Sovereign", "Sovereign", "Recharges Sovereign with plain Enchant Relics.")
    Toggle("Sovereign", 0, "SovAuto", "Recharge Sovereign power", "Every few reels, opens the inventory, searches for a plain Enchant Relic (no mutation), holds it, and clicks Enchant Rod and Confirm.")
    Stepper("Sovereign", 1, "SovEvery")
    Stepper("Sovereign", 2, "SovCount")
    ActionBtn("Sovereign", 3, "Recharge now", (*) => SetTimer(RechargeNow, -1), "Runs one recharge right away so you can watch it work.")
    UI.sovStatus := AddT("Sovereign", PAGE_X, RowBase + 4 * ROW_H + 4, LEFT_W, 50, "", "body", 9, Pal.dim, Pal.content)
    Pages["Sovereign"].desc := "Mutated relics are never used."
}

BuildAlerts() {
    PageHead("Alerts", "Alerts", "Discord messages about your session.")
    EditRow("Alerts", 0, "HookUrl", "Webhook link", "In Discord: Server Settings, Integrations, Webhooks, New Webhook, Copy Webhook URL. Paste it here.")
    EditRow("Alerts", 1, "HookUser", "Ping user ID", "Optional. Your Discord user ID, so problems and disconnects ping you.")
    Toggle("Alerts", 2, "HookErrors", "Problems", "A message, with a screenshot, when fishing stops because something went wrong.")
    Toggle("Alerts", 3, "HookDisconnect", "Disconnects and rejoins", "A message when Roblox disconnects and when the macro gets back in.")
    Toggle("Alerts", 4, "HookStart", "Started and stopped", "A message when fishing starts and when it stops normally.")
    Toggle("Alerts", 5, "HookJobs", "Aquarium, totems, recharges", "A message each time one of the between-catch jobs runs.")
    Stepper("Alerts", 6, "HookSummary")
    half := (LEFT_W - 12) // 2
    ActionBtn("Alerts", 7, "Send test message", (*) => SendTestAlert(), "Sends a test message to your webhook.", PAD, half)
    UI.hookStatus := AddT("Alerts", PAGE_X + half + 12, RowBase + 7 * ROW_H, half, 30, "", "body", 9, Pal.dim, Pal.content, "0x200")
    Pages["Alerts"].desc := ""
}

BuildReconnect() {
    PageHead("Reconnect", "Reconnect", "Rejoins after a disconnect.")
    Toggle("Reconnect", 0, "AutoReconnect", "Rejoin after a disconnect", "Watches Roblox's own log for a lost connection, then closes Roblox, rejoins and resumes fishing.")
    EditRow("Reconnect", 1, "RejoinLink", "Rejoin link", "Where to rejoin. Fisch by default. A private server link works if it has privateServerLinkCode in it.")
    Stepper("Reconnect", 2, "RejoinWait")
    Stepper("Reconnect", 3, "RejoinMax")
    Toggle("Reconnect", 4, "RejoinResume", "Equip the rod and resume", "After rejoining, clicks the game once and presses your rod key before fishing again.")
    ActionBtn("Reconnect", 5, "Check the Roblox log now", (*) => PaintReconnectStatus(), "Shows which Roblox log the watcher reads and the last disconnect line it saw.")
    UI.recStatus := AddT("Reconnect", PAGE_X, RowBase + 6 * ROW_H + 4, LEFT_W, 50, "", "body", 9, Pal.dim, Pal.content)
    Pages["Reconnect"].desc := "You may rejoin away from your fishing spot."
}

BuildSettings() {
    PageHead("Settings", "Settings", "Look, keys and updates.")
    Choice("Settings", 0, "Theme", "Theme", [["Black", "Black"], ["Dark", "Dark"], ["Light", "Light"], ["High contrast", "High contrast"]]
        , "Black uses only black, white and grays. Dark suits dim rooms, Light bright ones. High contrast uses black, white, yellow and cyan.")
    Stepper("Settings", 1, "Zoom")
    Toggle("Settings", 2, "MiniHud", "Small panel while fishing", "While fishing, hides this window and shows a small panel in the top-right corner with what's happening and a Stop button.")
    Toggle("Settings", 3, "OnTop", "Keep window on top", "Keeps this window above Roblox.")
    KeyBtn("Settings", 4, "ToggleKey", "Start and stop", "Works in any window, including Roblox.")
    KeyBtn("Settings", 5, "ExitKey", "Quit", "Closes the macro from any window.")
    half := (LEFT_W - 12) // 2
    ActionBtn("Settings", 6, "Check for updates", (*) => SetTimer(CheckForUpdate.Bind(false), -1), "Checks the update link for a newer version and shows what changed.", PAD, half)
    ActionBtn("Settings", 6, "What's new", (*) => ShowWhatsNew(), "Shows the changes in this version.", PAD + half + 12, half)
    EditRow("Settings", 7, "UpdateUrl", "Update link", "The address of the update file (update.json). Whoever controls it controls what the macro installs.")
    Pages["Settings"].desc := ""
}

; Advanced: the rod looks the macro has learned.
BuildRods() {
    PageHead("Rods", "Rod", "The rod in your hotbar and the reel style used for it.")
    AddT("Rods", PAGE_X, RowBase, 130, 28, "Equipped rod", "body", 10, Pal.dim, Pal.content, "0x200")
    UI.rodName := AddT("Rods", PAGE_X + 130, RowBase, LEFT_W - 130, 28, "–", "body", 10, Pal.text, Pal.content, "0x200")
    AddT("Rods", PAGE_X, RowBase + ROW_H, 130, 28, "Reel style", "body", 10, Pal.dim, Pal.content, "0x200")
    UI.rodStyle := AddT("Rods", PAGE_X + 130, RowBase + ROW_H, LEFT_W - 130, 28, "–", "body", 10, Pal.text, Pal.content, "0x200")
    ActionBtn("Rods", 2, "Read the rod now", (*) => SetTimer(ReadRodName.Bind(true), -1), "Reads the rod's name from its hotbar slot, using your rod key's slot.")
    names := ""
    for lib in RodLib
        names .= (names = "" ? "" : ", ") lib.name
    UI.rodNote := AddT("Rods", PAGE_X, RowBase + 3 * ROW_H + 4, LEFT_W, 80, "", "body", 9, Pal.dim, Pal.content)
    Pages["Rods"].desc := "Built-in reel styles: " names ". Other rods use the standard reel."
}

BuildLive() {
    global ColX, RowBase
    PageHead("Live", "Live view", "What FISCHXR sees in the reel.")
    UI.livePic := MainGui.Add("Picture", Format("x{} y{} w{} h{} Background000000", ZS(PAGE_X), ZS(76), ZS(LEFT_W), ZS(64)))
    Pages["Live"].ctls.Push(UI.livePic)
    UI.liveNone := AddT("Live", PAGE_X, 76, LEFT_W, 64, "Nothing to show yet. Start fishing, or press Preview with a reel on screen.", "body", 9, Pal.dim, Pal.field, "Center 0x200")
    labels := [["look", "Rod"], ["bar", "Bar"], ["fish", "Fish"], ["off", "Fish offset"], ["edges", "Reel outline"], ["cover", "Match"], ["rate", "Speed"], ["mode", "Status"]]
    cw := LEFT_W // 2
    for i, l in labels {
        c := (i - 1) // 4, r := Mod(i - 1, 4)
        x := PAGE_X + c * cw, y := 146 + r * 20
        AddT("Live", x, y, 78, 20, l[2], "body", 9, Pal.dim, Pal.content, "0x200")
        UI.liveVals[l[1]] := AddT("Live", x + 78, y, cw - 82, 20, "–", "body", 9, Pal.text, Pal.content, "0x200")
    }
    third := (LEFT_W - 16) // 3
    RowBase := 232
    UI.btnPreview := ActionBtn("Live", 0, "Preview", (*) => ToggleLivePreview(), "Shows the reel area live even when not fishing.", PAD, third)
    ActionBtn("Live", 0, "Save snapshot", (*) => SaveLiveSnapshot(), "Saves what the macro sees now, plus a report, to the Snapshots folder.", PAD + third + 8, third)
    ActionBtn("Live", 0, "Open snapshots", (*) => OpenSnapshots(), "Opens the Snapshots folder next to the macro.", PAD + 2 * (third + 8), third)
    RowBase := ROW_Y0
    AddT("Live", PAGE_X, 270, 200, 18, "Detection log", "body", 9, Pal.dim, Pal.content)
    UI.liveLog := AddT("Live", PAGE_X, 288, LEFT_W, 62, "", "body", 9, Pal.text, Pal.content)
    Pages["Live"].desc := ""
}

BuildReel() {
    PageHead("Reel", "Reel", "How the bar follows the fish.")
    Seg("Reel", 0, "ControlStyle", "Control style", [["physics", "Physics"], ["simple", "Simple"]]
        , "Physics learns how your rod's bar speeds up and slows down, then brakes so it stops on the fish. Simple predicts a fixed time ahead.")
    Stepper("Reel", 1, "Latency")
    Stepper("Reel", 2, "Braking")
    Stepper("Reel", 3, "EdgeMargin")
    Stepper("Reel", 4, "ScanDelay")
    Stepper("Reel", 5, "Predict")
    Toggle("Reel", 6, "ReelSnaps", "Record each reel's end", "Saves a screenshot, the reel band and a frame-by-frame report every time a reel ends, to Snapshots\Reels. Keeps the last 10.")
    Pages["Reel"].desc := ""
}

BuildTiming() {
    PageHead("Timing", "Timing", "Wait times.")
    for i, k in ["CastHold", "BobberWait", "BiteTimeout", "CatchDelay", "ShakeInterval", "ShakeTol", "TotemWait", "NightLevel"]
        Stepper("Timing", i - 1, k)
    Pages["Timing"].desc := ""
}

BuildMore() {
    PageHead("More", "More", "Other options.")
    Toggle("More", 0, "ColorSafe", "Color-blind safe colors", "Dark and Light themes: swaps teal, amber and coral for blue, yellow and orange.")
    Toggle("More", 1, "ReduceMotion", "Reduce motion", "Skips loading animations and slows the live gauge to a calm refresh.")
    Toggle("More", 2, "Speak", "Read status aloud", "Speaks status changes and the setting under keyboard focus with the Windows voice.")
    Toggle("More", 3, "Sounds", "Sound cues", "Plays a short sound when fishing starts, a reel finishes, or something needs attention.")
    Toggle("More", 4, "ShowSplash", "Show loading screen", "Shows the logo and startup steps while the macro opens.")
    Toggle("More", 5, "UseNavKey", "Press nav key first", "Presses the UI navigation key (\) before shaking. Only turn this on if Enter alone doesn't shake.")
    Toggle("More", 6, "HookShots", "Screenshots in alerts", "Adds a picture of the Roblox window to problem and disconnect messages.")
    UI.reset := ActionBtn("More", 7, "Reset all settings", (*) => ConfirmReset(), "Deletes FischMacro.ini, including learned rod looks, and restarts the macro.")
    Pages["More"].desc := ""
}

PageHead(page, title, intro) {
    AddT(page, PAGE_X, 12, LEFT_W - 90, 30, title, "display", 15, Pal.text, Pal.content, "0x200")
    AddT(page, PAGE_X, 44, LEFT_W, 32, intro, "body", 9, Pal.dim, Pal.content)
}

; (Kept for older page code: one column only now.)
Col(page, n, heading := "") {
    global ColX, RowBase
    ColX := PAGE_X - PAD, RowBase := ROW_Y0
}

;------------------------------------------------------------------------------
; Row controls. Each registers its clickable parts, hover help and a keyboard
; focus item (name, activate, adjust, spoken value, help text). ColX shifts a
; row into the right-hand column; RowBase is where row 0 sits.
;------------------------------------------------------------------------------
Stepper(page, row, key, swatchKey := "") {
    sp := NumSpec[key], y := RowBase + row * ROW_H, ox := ColX, lx := PAD + ox
    lab := AddT(page, lx, y, 290, 28, sp.label, "body", 10, Pal.text, Pal.content, "0x200")
    minus := AddT(page, ox + 318, y, 28, 28, "−", "body", 12, Pal.dim, Pal.field, "Center 0x200")
    val := AddT(page, ox + 348, y, 64, 28, StepText(key), "num", 11, Pal.text, Pal.field, "Center 0x200")
    plus := AddT(page, ox + 414, y, 28, 28, "+", "body", 12, Pal.dim, Pal.field, "Center 0x200")
    unit := AddT(page, ox + 446, y, 34, 28, StepUnit(key), "body", 9, Pal.dim, Pal.content, "0x200")
    UI.units[key] := unit
    Clickables[minus.Hwnd] := {kind: "step", key: key, dir: -1, obj: minus, bg: Pal.field, hv: Pal.fieldHi}
    Clickables[plus.Hwnd] := {kind: "step", key: key, dir: 1, obj: plus, bg: Pal.field, hv: Pal.fieldHi}
    Clickables[val.Hwnd] := {kind: "value", key: key, obj: val}
    Steppers[key] := val
    for c in [lab, minus, val, plus, unit]
        DescOf[c.Hwnd] := sp.help
    AddFocus(page, [minus, val, plus], sp.label, 0, StepSetting.Bind(key), SpokenValue.Bind(key), sp.help)
}

Toggle(page, row, key, label, desc) {
    y := RowBase + row * ROW_H, ox := ColX
    lab := AddT(page, PAD + ox, y, 340, 28, label, "body", 10, Pal.text, Pal.content, "0x200")
    t := AddT(page, ox + 382, y, 60, 28, "Off", "body", 9, Pal.dim, Pal.field, "Center 0x200")
    Clickables[t.Hwnd] := {kind: "toggle", key: key, obj: t}
    Toggles[key] := t
    DescOf[lab.Hwnd] := desc, DescOf[t.Hwnd] := desc
    PaintToggle(key)
    AddFocus(page, [t], label, FlipToggle.Bind(key), ToggleAdj.Bind(key), SpokenValue.Bind(key), desc)
}

KeyBtn(page, row, key, label, desc) {
    y := RowBase + row * ROW_H, ox := ColX
    lab := AddT(page, PAD + ox, y, 300, 28, label, "body", 10, Pal.text, Pal.content, "0x200")
    b := AddT(page, ox + 346, y, 96, 28, Cfg[key] = "" ? "Not set" : KeyName(Cfg[key]), "num", 10, Pal.text, Pal.field, "Center 0x200")
    Clickables[b.Hwnd] := {kind: "key", key: key, obj: b, bg: Pal.field, hv: Pal.fieldHi}
    KeyBtns[key] := b
    DescOf[lab.Hwnd] := desc, DescOf[b.Hwnd] := desc
    AddFocus(page, [b], label, CaptureKeyFor.Bind(key), 0, SpokenValue.Bind(key), desc " Press Enter, then the new key.")
}

Seg(page, row, key, label, options, desc) {
    y := RowBase + row * ROW_H, n := options.Length, sw := 96, ox := ColX
    x := ox + 442 - n * sw - (n - 1) * 2
    lab := AddT(page, PAD + ox, y, x - PAD - ox - 8, 28, label, "body", 10, Pal.text, Pal.content, "0x200")
    DescOf[lab.Hwnd] := desc
    SegCtls[key] := []
    ctls := []
    for o in options {
        s := AddT(page, x, y, sw, 28, o[2], "body", 9, Pal.dim, Pal.field, "Center 0x200")
        Clickables[s.Hwnd] := {kind: "seg", key: key, value: o[1], obj: s}
        SegCtls[key].Push({ctl: s, value: o[1], text: o[2]})
        DescOf[s.Hwnd] := desc
        ctls.Push(s)
        x += sw + 2
    }
    PaintSegs(key)
    AddFocus(page, ctls, label, CycleChoice.Bind(key, 1), CycleChoice.Bind(key), SpokenValue.Bind(key), desc)
}

Choice(page, row, key, label, options, desc) {
    y := RowBase + row * ROW_H, ox := ColX
    lab := AddT(page, PAD + ox, y, 230, 28, label, "body", 10, Pal.text, Pal.content, "0x200")
    c := AddT(page, ox + 262, y, 180, 28, "", "body", 9, Pal.text, Pal.field, "Center 0x200")
    Clickables[c.Hwnd] := {kind: "choice", key: key, obj: c, bg: Pal.field, hv: Pal.fieldHi}
    Choices[key] := {ctl: c, options: options}
    DescOf[lab.Hwnd] := desc, DescOf[c.Hwnd] := desc
    PaintChoice(key)
    AddFocus(page, [c], label, OpenChoiceMenu.Bind(key), CycleChoice.Bind(key), SpokenValue.Bind(key), desc " Arrow keys change it.")
}

ActionBtn(page, row, text, fn, desc, x := PAD, w := LEFT_W) {
    y := RowBase + row * ROW_H
    b := AddT(page, x + ColX, y, w, 30, text, "body", 10, Pal.text, Pal.field, "Center 0x200")
    Clickables[b.Hwnd] := {kind: "btn", fn: fn, obj: b, bg: Pal.field, hv: Pal.fieldHi}
    DescOf[b.Hwnd] := desc
    AddFocus(page, [b], text, fn, 0, 0, desc)
    return b
}

; A labelled one-line text field bound to a text setting.
EditRow(page, row, key, label, desc) {
    y := RowBase + row * ROW_H, ox := ColX
    lab := AddT(page, PAD + ox, y, 126, 28, label, "body", 10, Pal.text, Pal.content, "0x200")
    e := AddEdit(page, PAD + ox + 128, y, LEFT_W - 128, 28, Cfg[key], key)
    DescOf[lab.Hwnd] := desc
    AddFocus(page, [e], label, FocusEdit.Bind(e), 0, () => Cfg[key] = "" ? "empty" : "filled in", desc " Press Enter to type.")
    return e
}

AddEdit(page, x, y, w, h, value, key) {
    SetFontFor(MainGui, "norm s" FZ(10) " c" Pal.text, "body")
    e := MainGui.Add("Edit", Format("x{} y{} w{} h{} -E0x200 -Wrap r1 Background{}", ZS(x), ZS(y) + ZS(3), ZS(w), ZS(h) - ZS(4), Pal.field), value)
    if (page != 0)
        Pages[page].ctls.Push(e)
    EditCtls[e.Hwnd] := {key: key, ctl: e}
    if (key != "rename")
        e.OnEvent("Change", EditChanged.Bind(key))
    return e
}

Tile(page, x, y, w, h, title, sub, fn, primary := false) {
    bg := primary ? Pal.accent : Pal.field, hv := primary ? Pal.accentHi : Pal.fieldHi
    fg := primary ? Pal.ink : Pal.text, fg2 := primary ? Pal.ink : Pal.dim
    lp := AddT(page, x, y, 16, h, "", "body", 9, fg, bg)
    t := AddT(page, x + 16, y, w - 16, 40, title, "display", 12, fg, bg, "0x200")
    s := AddT(page, x + 16, y + 40, w - 16, h - 40, sub, "body", 9, fg2, bg)
    e := {kind: "btn", fn: fn, obj: t, objs: [lp, t, s], bg: bg, hv: hv}
    for c in [lp, t, s]
        Clickables[c.Hwnd] := e
    AddFocus(page, [lp, t, s], title, fn, 0, 0, sub)
    return {title: t, sub: s, entry: e}
}

AddFocus(page, ctls, name, act, adj, value, desc) {
    item := {ctls: ctls, name: name, act: act, adj: adj, value: value, desc: desc}
    Pages[page].focus.Push(item)
    return item
}

;------------------------------------------------------------------------------
; Showing, switching and laying out
;------------------------------------------------------------------------------
ShowMain(tab, px := "", py := "") {
    SwitchTab(tab, false)
    w := ZS(Cfg["WinW"]), h := ZS(Cfg["WinH"])
    MonitorGetWorkArea(, &L, &T, &R, &B)
    w := Min(w, Floor((R - L) * 96 / A_ScreenDPI)), h := Min(h, Floor((B - T) * 96 / A_ScreenDPI))
    x := px != "" ? px : Cfg["WinX"], y := py != "" ? py : Cfg["WinY"]
    pos := ""
    if (IsNumber(x) && IsNumber(y) && PointOnScreen(Integer(x) + 60, Integer(y) + 20))
        pos := Format("x{} y{} ", Integer(x), Integer(y))
    MainGui.Show(pos "w" w " h" h)
    StyleWindow(MainGui.Hwnd)
    try ApplyAppIcon(MainGui.Hwnd)
    Layout()
    UpdateAll()
}

SwitchTab(name, speak := true) {
    global CurTab, FocusOn
    if !Pages.Has(name)
        return
    if (CurTab = "Rods" && name != "Rods")
        try CommitRename(false)
    CurTab := name
    for t, pg in Pages
        for c in pg.ctls
            c.Visible := (t = name)
    ; an Advanced page brings the Advanced tabs into the sidebar, and back
    mode := "basic"
    for t in AdvTabs
        if (t = name)
            mode := "adv"
    UI.navMode := mode
    UI.desc.Visible := (name != "Home")        ; hover help and messages show here
    UI.desc.Text := Pages[name].desc
    PaintTabs()
    SlideIn(Pages[name].ctls)
    switch name {
        case "Rods": RodsChanged()
        case "Sovereign": PaintSovStatus()
        case "Totems": TotemsChanged()
        case "Alerts": PaintHookStatus()
        case "Reconnect": PaintReconnectStatus()
        case "Live": LiveShow()
    }
    if (name != "Live")
        SetTimer(LiveTick, 0)
    if UiReady
        Layout()
    if FocusOn {
        FocusOn := false
        HideRing()
    }
    if (name != "Home" && Cfg["LastTab"] != name) {
        Cfg["LastTab"] := name
        Save("LastTab")
    }
    if speak
        Say(name " tab")
}

CycleTab(dir) {
    list := UI.navMode = "adv" ? AdvTabs : BasicTabs
    for i, t in list
        if (t = CurTab)
            return SwitchTab(list[Mod(i - 1 + dir + list.Length, list.Length) + 1])
    SwitchTab(list[1])
}

PaintTabs() {
    for name, row in UI.navRows {
        on := (name = CurTab), e := row.entry
        e.bg := on ? Pal.field : Pal.strip, e.hv := on ? Pal.field : Pal.fieldHi
        for c in [row.icon, row.label] {
            c.Opt("Background" e.bg)
            c.SetFont("c" (on ? Pal.text : Pal.dim))
            c.Redraw()
        }
        row.mark.Opt("Background" (on ? Pal.accent : Pal.strip))
        row.mark.Redraw()
        vis := (row.mode = UI.navMode)
        for c in [row.mark, row.icon, row.label]
            c.Visible := vis
    }
}

Layout() {
    if (!UiReady || !IsObject(MainGui))
        return
    MainGui.GetClientPos(, , &W, &H)
    UI.btnClose.Move(W - ZS(40), 0)
    UI.btnMin.Move(W - ZS(80), 0)
    UI.startBtn.Move(, H - ZS(52))
    x0 := ZS(PAGE_X), cw := Max(ZS(300), W - x0 - ZS(16))
    for c in [UI.dStatus, UI.dDetail, UI.sep1, UI.sep2, UI.evHead, UI.hRbx]
        c.Move(, , c = UI.hRbx ? cw - ZS(16) : cw)
    for c in [UI.iRod, UI.iPhys, UI.iAq, UI.iRbx]
        c.Move(, , cw - ZS(80))
    UI.mCtrL.Move(x0 + cw // 2), UI.mCtr.Move(x0 + cw // 2 + ZS(66))
    UI.events.Move(, , cw, Max(ZS(20), H - ZS(STATUS_H) - ZS(6) - ZS(322)))
    UI.desc.Move(x0, H - ZS(STATUS_H) - ZS(36), cw, ZS(34))
    UI.livePic.Move(x0, ZS(76), cw, ZS(64))
    UI.liveNone.Move(x0, ZS(76), cw, ZS(64))
    UI.liveLog.Move(, , cw, Max(ZS(20), H - ZS(STATUS_H) - ZS(40) - ZS(288)))
    UI.gX := x0, UI.gW := cw
    SetGauge(GaugeState.l, GaugeState.r, GaugeState.f, GaugeState.live)
    y := H - ZS(STATUS_H)
    for it in UI.sbLeft
        it.ctl.Move(, y + ZS(it.dy))
    for it in UI.sbRight
        it.ctl.Move(W - ZS(it.off), y + ZS(it.dy))
    if FocusOn
        try ShowFocus(FocusList()[FocusIdx], false)
    DllCall("InvalidateRect", "Ptr", MainGui.Hwnd, "Ptr", 0, "Int", 1)
}

UpdateAll() {
    PaintPhase()
    UpdateStats()
    UpdateStartControls()
    PaintChips()
    UpdateEvents()
    RefreshRobloxInfo()
}

ToggleMaximize() {
    global Maxed, NormalRect
    hwnd := MainGui.Hwnd
    if !Maxed {
        WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
        NormalRect := {x: x, y: y, w: w, h: h}
        MonitorGetWorkArea(MonitorAt(x + w // 2, y + h // 2), &L, &T, &R, &B)
        SizeWindow(hwnd, L, T, R - L, B - T)
        Maxed := true
    } else {
        SizeWindow(hwnd, NormalRect.x, NormalRect.y, NormalRect.w, NormalRect.h)
        Maxed := false
    }
    try UI.btnMax.Text := IconOr(Chr(Maxed ? 0xE923 : 0xE922), Maxed ? "❐" : "□")
    Layout()
}

; Drag-resize from the right edge, bottom edge or bottom-right corner.
ResizeLoop(zone) {
    if Maxed
        return
    hwnd := MainGui.Hwnd
    WinGetPos(, , &w0, &h0, "ahk_id " hwnd)
    MouseGetPos(&mx0, &my0)
    minW := ToPhys(MIN_W), minH := ToPhys(MIN_H), lw := w0, lh := h0
    while GetKeyState("LButton", "P") {
        MouseGetPos(&mx, &my)
        nw := InStr(zone, "r") ? Max(minW, w0 + mx - mx0) : w0
        nh := InStr(zone, "b") ? Max(minH, h0 + my - my0) : h0
        if (nw != lw || nh != lh) {
            ; WM_SETREDRAW off clears WS_VISIBLE on a top-level window, so the
            ; window is resized by handle rather than looked up by title.
            DllCall("SendMessage", "Ptr", hwnd, "UInt", 0x000B, "Ptr", 0, "Ptr", 0)
            SizeWindow(hwnd, "", "", nw, nh)
            Layout()
            DllCall("SendMessage", "Ptr", hwnd, "UInt", 0x000B, "Ptr", 1, "Ptr", 0)
            DllCall("RedrawWindow", "Ptr", hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x585)
            lw := nw, lh := nh
        }
        Sleep 15
    }
    SaveGeometry()
}

; Moves and/or sizes a window by handle, in physical pixels. Blank x/y keeps the position.
SizeWindow(hwnd, x, y, w, h) {
    flags := 0x0014 | (x = "" ? 0x0002 : 0)      ; NOZORDER | NOACTIVATE [| NOMOVE]
    DllCall("SetWindowPos", "Ptr", hwnd, "Ptr", 0, "Int", x = "" ? 0 : x, "Int", y = "" ? 0 : y, "Int", w, "Int", h, "UInt", flags)
}

SaveGeometry() {
    if (!IsObject(MainGui) || !UiReady)
        return
    try {
        if (WinGetMinMax("ahk_id " MainGui.Hwnd) != 0)
            return
        if Maxed {
            Cfg["WinX"] := NormalRect.x, Cfg["WinY"] := NormalRect.y
        } else {
            MainGui.GetPos(&x, &y)
            MainGui.GetClientPos(, , &w, &h)
            Cfg["WinX"] := x, Cfg["WinY"] := y
            Cfg["WinW"] := Max(MIN_W, Round(w / Zoom)), Cfg["WinH"] := Max(MIN_H, Round(h / Zoom))
            Save("WinW"), Save("WinH")
        }
        Save("WinX"), Save("WinY")
    }
}

RebuildGui() {
    global UiReady, Zoom, FocusOn, FocusIdx, Maxed
    if !IsObject(MainGui)
        return
    SaveGeometry()
    try WinGetPos(&wx, &wy, , , "ahk_id " MainGui.Hwnd)
    if Maxed
        wx := NormalRect.x, wy := NormalRect.y, Maxed := false
    tab := CurTab, fOn := FocusOn, fIdx := FocusIdx
    UiReady := false
    Dialog.Close()
    DestroyOverlays()
    old := MainGui, oldLogo := UI.HasOwnProp("logoHbm") ? UI.logoHbm : 0
    ResolveTheme()
    Zoom := Cfg["Zoom"] / 100
    FreeBrushes()
    BuildGui()
    ShowMain(tab, IsSet(wx) ? wx : "", IsSet(wy) ? wy : "")
    try old.Destroy()
    if oldLogo
        DllCall("DeleteObject", "Ptr", oldLogo)
    if fOn {
        list := FocusList()
        if list.Length {
            FocusOn := true, FocusIdx := Min(fIdx, list.Length)
            ShowFocus(list[FocusIdx], false)
        }
    }
    if Cfg["ShowAreas"]
        UpdateOverlay()
}

;------------------------------------------------------------------------------
; Painting state onto controls
;------------------------------------------------------------------------------
PaintToggle(key) {
    if Toggles.Has(key) {
        t := Toggles[key], on := Cfg[key]
        t.Opt("Background" (on ? Pal.accent : Pal.field))
        t.SetFont(on ? "w600 c" Pal.ink : "w400 c" Pal.dim)
        t.Text := on ? "On" : "Off"
        t.Redraw()
    }
    PaintChips()
}

PaintChips() {
    if !UI.HasOwnProp("chips")
        return
    for key, c in UI.chips {
        on := Cfg[key]
        c.Opt("Background" (on ? Pal.field : Pal.bar))
        c.SetFont("c" (on ? Pal.accent : Pal.dim))
        c.Redraw()
    }
}

PaintSegs(key) {
    if !SegCtls.Has(key)
        return
    for s in SegCtls[key] {
        on := (Cfg[key] = s.value)
        s.ctl.Opt("Background" (on ? Pal.accent : Pal.field))
        s.ctl.SetFont(on ? "w600 c" Pal.ink : "w400 c" Pal.dim)
        s.ctl.Redraw()
    }
}

PaintChoice(key) {
    if Choices.Has(key)
        Choices[key].ctl.Text := ChoiceText(key) "  ▼"
}

ChoiceText(key) {
    if Choices.Has(key)
        for o in Choices[key].options
            if (o[1] = Cfg[key])
                return o[2]
    if SegCtls.Has(key)
        for s in SegCtls[key]
            if (s.value = Cfg[key])
                return s.text
    return Cfg[key]
}

UpdateStartControls() {
    if !UiReady
        return
    try {
        b := UI.startBtn, e := Clickables[b.Hwnd]
        busy := Running || AqManual, k := KeyName(Cfg["ToggleKey"])
        e.bg := busy ? Pal.field : Pal.accent, e.hv := busy ? Pal.fieldHi : Pal.accentHi
        b.Text := (busy ? "■  Stop" : "►  Start") "  " k
        b.SetFont("c" (busy ? Pal.stop : Pal.ink))
        b.Opt("Background" (Hover = b.Hwnd ? e.hv : e.bg))
        b.Redraw()
    }
}

PhaseColor(kind) {
    if (kind = "wait" || kind = "pause")
        return Pal.wait
    if (kind = "reel" || kind = "aqua")
        return Pal.accent
    if (kind = "error")
        return Pal.stop
    return Pal.text
}

SetPhase(kind, title, detail := "") {
    if (!Running && !AqManual && kind != "idle" && kind != "error")
        return
    changed := (title != Phase.title)
    Phase.kind := kind, Phase.title := title, Phase.detail := detail
    PaintPhase()
    if changed {
        try MainGui.Title := APP_NAME " - " title
        A_IconTip := SubStr(APP_NAME ": " title, 1, 120)
        if (title != "Casting" && title != "Waiting for a bite")
            Say(title)
        if (kind = "pause")
            Cue("pause")
    }
}

PaintPhase() {
    if !UiReady
        return
    try {
        col := PhaseColor(Phase.kind)
        if (UI.dStatus.Text != Phase.title)
            UI.dStatus.Text := Phase.title
        if (UI.sbStatus.Text != Phase.title)
            UI.sbStatus.Text := Phase.title
        if (col != UI.phaseColor) {
            UI.dStatus.SetFont("c" col), UI.sbDot.SetFont("c" col)
            UI.phaseColor := col
        }
        det := (Phase.detail = "" && Phase.kind = "idle") ? IdleHint() : Phase.detail
        if (UI.dDetail.Text != det)
            UI.dDetail.Text := det
    }
    Hud.Update()
}

SetDetail(text) {
    Phase.detail := text
    if !UiReady
        return
    try {
        if (UI.dDetail.Text != text)
            UI.dDetail.Text := text
    }
}

; l, r and f are fractions of the reel track. f < 0 leaves the fish tick alone.
SetGauge(l, r, f, live) {
    GaugeState.l := l, GaugeState.r := r, GaugeState.live := live
    if (f >= 0)
        GaugeState.f := f
    Hud.Gauge(l, r, GaugeState.f, live)
    if !UiReady
        return
    try {
        w := UI.gW, x0 := UI.gX
        bl := Round(Clamp(l, 0, 1) * w), br := Round(Clamp(r, 0, 1) * w)
        if (br - bl < 2)
            br := Min(w, bl + 2), bl := br - 2
        UI.gL.Move(x0, , bl)
        UI.gBar.Move(x0 + bl, , br - bl)
        UI.gR.Move(x0 + br, , w - br)
        UI.gCtr.Move(x0 + (bl + br) // 2 - 1)
        UI.gFish.Move(x0 + Round(Clamp(GaugeState.f, 0, 1) * (w - 3)))
        if (live != UI.gLive) {
            UI.gLive := live
            UI.gBar.Opt("Background" (live ? Pal.accent : Pal.faint))
            UI.gFish.Opt("Background" (live ? Pal.text : Pal.faint))
            UI.gCtr.Opt("Background" (live ? Pal.dim : Pal.faint))
            UI.gBar.Redraw(), UI.gFish.Redraw(), UI.gCtr.Redraw()
            if !live {
                UI.mOff.Text := "–"
                UI.mCtr.Text := "–"
            }
        }
    }
}

SetLive(offset, centered) {
    if !UiReady
        return
    try {
        t1 := (offset = "") ? "–" : Format("{:+d}%", Round(offset * 100))
        t2 := (centered = "") ? "–" : Round(centered * 100) "%"
        if (UI.mOff.Text != t1)
            UI.mOff.Text := t1
        if (UI.mCtr.Text != t2)
            UI.mCtr.Text := t2
    }
}

UpdateStats() {
    if !UiReady
        return
    try {
        UI.sbCasts.Text := "Casts " Stats.casts
        UI.sbReels.Text := "Reels " Stats.reels
    }
    Hud.Update()
}

TickClock() {
    secs := (A_TickCount - Stats.start) // 1000
    if UiReady
        try {
            UI.sbTime.Text := Format("{}:{:02}:{:02}", secs // 3600, Mod(secs // 60, 60), Mod(secs, 60))
            Hud.Update()
            if (Mod(secs, 5) = 0) {
                t := NextJobText()
                if (UI.iAq.Text != t)
                    UI.iAq.Text := t
                if (CurTab = "Totems")
                    TotemsChanged()
            }
        }
}

; The soonest between-catch job, for the dashboard.
NextJobText() {
    jobs := []
    if Cfg["AqAuto"]
        jobs.Push(["Aquarium", AqNext])
    if Cfg["TotemAuto"]
        for t in Totems
            if (t.on && t.slot != "")
                jobs.Push([t.name " Totem", t.next])
    if !jobs.Length
        return Cfg["SovAuto"] ? "Sovereign recharge, every " Cfg["SovEvery"] " reels" : "None scheduled"
    if !Running
        return jobs.Length " job" (jobs.Length = 1 ? "" : "s") " scheduled"
    best := jobs[1]
    for j in jobs
        if (j[2] < best[2])
            best := j
    m := Max(0, Round((best[2] - A_TickCount) / 60000))
    return best[1] (m ? " in " m " min" : " next")
}

UpdateRodInfo(p, frac, key) {
    global RodInfoText
    RodInfoText := p.name
    if UiReady
        try {
            UI.iRod.Text := RodInfoText
            RodsChanged()
            if (CurTab = "Rods")
                RodsChanged()
            Hud.Update()
        }
}

PhysicsText(key := "") {
    if (Cfg["ControlStyle"] = "simple")
        return "Simple look-ahead, " Cfg["Predict"] " ms"
    if (Cfg["Latency"] > 0)
        lagTxt := ", " Cfg["Latency"] " ms lag (set)"
    else
        lagTxt := Cfg["LearnedLag"] > 0 ? ", " Cfg["LearnedLag"] " ms lag" : ", measuring lag"
    if (key != "" && RodMem.Has(key)) {
        n := RodMem[key].n
        return "Learned from " n " reel" (n = 1 ? "" : "s") lagTxt
    }
    return (key != "" ? "Learning this rod" : "Learns each rod") lagTxt
}

RodSegText() {
    return "Rod: " (IsObject(CurRod) ? CurRod.name : "not seen yet")
}

LogEvent(text) {
    Events.InsertAt(1, FormatTime(, "HH:mm") "   " text)
    if (Events.Length > 30)
        Events.Pop()
    UpdateEvents()
}

UpdateEvents() {
    if UiReady
        try UI.events.Text := EventsText()
}

EventsText() {
    s := ""
    for i, e in Events {
        if (i > 6)
            break
        s .= (s = "" ? "" : "`n") e
    }
    return s = "" ? "Nothing yet." : s
}

StepUnit(key) {
    t := StepText(key)
    return (t = "Auto" || t = "Off") ? "" : NumSpec[key].unit
}

;------------------------------------------------------------------------------
; Rods tab
;------------------------------------------------------------------------------
RodsTileText() {
    n := RodProfiles.Length
    if !n
        return "Learned on the first reel with each"
    return n " look" (n = 1 ? "" : "s") " learned" (IsObject(CurRod) ? ", using " CurRod.name : "")
}

RodsChanged() {
    if (!UiReady || !UI.HasOwnProp("rodName"))
        return
    UI.rodName.Text := CurRodName != "" ? CurRodName : RodReadBusy ? "Reading…" : "Not read yet"
    style := "–"
    if (CurRodLib != "")
        style := RodById(CurRodLib).name
    else if IsObject(CurRod)
        style := RodById(CurRod.lib).name " (from the reel)"
    UI.rodStyle.Text := style
    UI.rodNote.Text := RodReadLast
    try UI.iPhys.Text := style
    if (CurRodName != "")
        try UI.iRod.Text := CurRodName
}





CommitRename(keep) => 0



PaintSovStatus() {
    if !UiReady
        return
    s := Cfg["SovAuto"] ? "On. Every " Cfg["SovEvery"] " reels it uses " Cfg["SovCount"] " plain Enchant Relic" (Cfg["SovCount"] = 1 ? "" : "s") " (no mutation) from your inventory." : "Off."
    if (SovLast != "")
        s .= "`nLast recharge " SovLast "."
    else if Cfg["SovAuto"]
        s .= "`nNext after " Max(0, Cfg["SovEvery"] - SovReels) " more reel" (Cfg["SovEvery"] - SovReels = 1 ? "" : "s") "."
    try UI.sovStatus.Text := s
}

Join(list, sep) {
    s := ""
    for v in list
        s .= (A_Index = 1 ? "" : sep) v
    return s
}

;------------------------------------------------------------------------------
; Totems tab
;------------------------------------------------------------------------------
TotemsChanged() {
    if (!UiReady || !UI.totemRows.Length)
        return
    on := CurTab = "Totems"
    for i, r in UI.totemRows {
        show := on && i <= Totems.Length
        for c in [r.on, r.name, r.night, r.key, r.less, r.every, r.more, r.unit, r.del]
            c.Visible := show
        if (i > Totems.Length)
            continue
        t := Totems[i]
        r.on.Text := t.on ? "On" : "Off"
        r.on.Opt("Background" (t.on ? Pal.accent : Pal.field)), r.on.SetFont(t.on ? "w600 c" Pal.ink : "w400 c" Pal.dim)
        r.name.Text := t.name
        r.name.SetFont("c" (t.on ? Pal.text : Pal.dim))
        r.night.Opt("Background" (t.night ? Pal.fieldHi : Pal.field)), r.night.SetFont("c" (t.night ? Pal.text : Pal.faint))
        r.key.Text := t.slot = "" ? "Key?" : KeyName(t.slot)
        r.key.SetFont("c" (t.slot = "" ? Pal.wait : Pal.text))
        r.every.Text := t.every
        for c in [r.on, r.name, r.night, r.key, r.every]
            c.Redraw()
    }
    full := Totems.Length >= TOTEM_MAX
    UI.btnAddTotem.Text := full ? "Six totems scheduled" : "+  Add a totem"
    UI.btnAddTotem.SetFont("c" (full ? Pal.faint : Pal.text)), UI.btnAddTotem.Redraw()
    noKey := 0
    for t in Totems
        noKey += (t.slot = "")
    msg := !Totems.Length ? "Nothing scheduled. Add the totems you own." : noKey ? "Set the hotbar key for each totem, or it is skipped." : TotemNextText()
    Pages["Totems"].desc := msg
    if (CurTab = "Totems")
        UI.desc.Text := msg
}

TotemNextText() {
    if !Cfg["TotemAuto"]
        return "Totems are off. Turn on 'Use totems while fishing' to run the schedule."
    if !Running
        return "Each totem is used shortly after fishing starts, then on its schedule."
    s := ""
    for t in Totems
        if (t.on && t.slot != "")
            s .= (s = "" ? "Next: " : ", ") t.name " in " Max(0, Round((t.next - A_TickCount) / 60000)) " min"
    return s = "" ? "No totem has a key set." : s
}

TotemOp(op, i, *) {
    if (i > Totems.Length)
        return
    t := Totems[i]
    switch op {
        case "on": t.on := !t.on
        case "night": t.night := !t.night
        case "less": t.every := Max(1, t.every - 1)
        case "more": t.every := Min(240, t.every + 1)
        case "del": return RemoveTotem(i)
        case "name": return SetTimer(OpenTotemMenu.Bind(i), -1)
        case "key": return SetTimer(CaptureKeyFor.Bind("Totem:" i), -1)
    }
    SaveTotems()
    TotemsChanged()
}

TotemAdj(i, dir, *) => TotemOp(dir > 0 ? "more" : "less", i)
TotemSpoken(i, *) => i <= Totems.Length ? Totems[i].name ", " (Totems[i].on ? "on" : "off") ", every " Totems[i].every " minutes" : "empty"

; Menu of totem names: adds one (i = 0) or changes row i.
OpenTotemMenu(i, *) {
    global MenuOpen
    if (MenuOpen || (!i && Totems.Length >= TOTEM_MAX))
        return
    m := Menu()
    for p in TotemPresets
        m.Add(p[1] " Totem", TotemPicked.Bind(i, p[1], p[2]))
    WinGetPos(&x, &y, &w, &h, "ahk_id " (i ? UI.totemRows[i].name.Hwnd : UI.btnAddTotem.Hwnd))
    MenuOpen := true
    try m.Show(x, y + h)
    MenuOpen := false
}

TotemPicked(i, name, night, *) {
    if !i
        return AddTotem(name)
    Totems[i].name := name, Totems[i].night := night
    SaveTotems()
    TotemsChanged()
}

;------------------------------------------------------------------------------
; Alerts tab
;------------------------------------------------------------------------------
EditChanged(key, ctl, *) {
    v := Trim(ctl.Value)
    if (Cfg[key] = v)
        return
    Cfg[key] := v
    Save(key)
    if (key = "HookUrl")
        PaintHookStatus()
}

FocusEdit(e, *) {
    e.Focus()
    SendMessage(0xB1, 0, -1, e)
}

PaintHookStatus() {
    if !UiReady
        return
    u := Cfg["HookUrl"]
    s := HookLast != "" ? HookLast : u = "" ? "No webhook link yet." : HookUrlOk(u) ? "Link looks right." : "That isn't a Discord webhook link."
    try UI.hookStatus.Text := s
}

PaintReconnectStatus() {
    if !UiReady
        return
    try UI.recStatus.Text := ReconnectStatusText()
}

;------------------------------------------------------------------------------
; Live tab: what the macro sees, redrawn a few times a second while open.
;------------------------------------------------------------------------------
LiveShow() {
    LiveLogChanged()
    LiveTick()
    SetTimer(LiveTick, (Running || LivePreview) ? 150 : 1000)
}

ToggleLivePreview() {
    global LivePreview
    LivePreview := !LivePreview
    UI.btnPreview.Text := LivePreview ? "Stop preview" : "Preview"
    SetTimer(LiveTick, LivePreview ? 150 : 1000)
    LiveTick()
}

; The frame to show: the macro's own while fishing, else a fresh grab of the
; reel area when previewing. Returns {b, d, p, ep, mode} or 0.
LiveSource() {
    global PreviewBand, PreviewGeo
    if (Running && IsObject(LiveBand)) {
        reeling := LiveT && A_TickCount - LiveT < 400
        return {b: LiveBand, d: reeling ? LiveD : 0, p: reeling ? LiveP : CurRod, ep: reeling ? LiveEp : -2
            , mode: reeling ? "Reeling" : Phase.title}
    }
    if !LivePreview
        return 0
    h := (RobloxHwnd && WinExist("ahk_id " RobloxHwnd)) ? RobloxHwnd : FindRoblox()
    cr := h ? ClientRect(h) : 0
    if !cr
        return 0
    geo := VisionGeo(AreaRect("Reel", cr))
    if (!IsObject(PreviewBand) || PreviewBand.w != geo.w || PreviewBand.h != geo.h)
        PreviewBand := BandGrab(geo.w, geo.h)
    PreviewGeo := geo
    VisionGrab(PreviewBand, geo)
    p := IsObject(CurRod) ? CurRod : (RodProfiles.Length ? RodProfiles[1] : 0)
    d := p ? VisionScan(PreviewBand, p) : 0
    return {b: PreviewBand, d: d, p: p, ep: p ? EdgesPresent(PreviewBand, geo, p) : -2
        , mode: "Preview" (p ? ", read with " p.name : ", no look learned yet")}
}

LiveTick() {
    global LiveHbm
    if (!UiReady || CurTab != "Live") {
        SetTimer(LiveTick, 0)
        return
    }
    src := LiveSource()
    UI.liveNone.Visible := !src
    UI.livePic.Visible := !!src
    V := UI.liveVals
    if !src {
        for k, c in V
            c.Text := "–"
        V["mode"].Text := Running ? Phase.title : "Idle. Press Preview to watch the reel area."
        return
    }
    b := src.b, d := src.d, p := src.p
    UI.livePic.GetPos(, , &pw, &ph)
    hbm := VisionPicture(b, d, pw, ph, Pal.HasOwnProp("mono"))
    old := LiveHbm, LiveHbm := hbm
    UI.livePic.Value := "HBITMAP:*" hbm
    if old
        DllCall("DeleteObject", "Ptr", old)
    V["look"].Text := IsObject(p) ? p.name (p.sovereign ? "  ·  Sovereign" : "") : "none learned yet"
    V["bar"].Text := (d && d.bar) ? Format("found, {}% of the track", Round(100 * (d.br - d.bl + 1) / b.w)) : d ? "not found" : "–"
    V["fish"].Text := (d && d.fish) ? (d.fishCol ? "found" : "found by contrast") : d ? "not found" : "–"
    V["off"].Text := (d && d.bar && d.fish) ? Format("{:+d}% of half the bar", Round(100 * (d.fx - (d.bl + d.br) / 2) / Max(1, (d.br - d.bl) / 2))) : "–"
    V["edges"].Text := src.ep = 1 ? "outline found" : src.ep = 0 ? "outline missing" : src.ep = -1 ? "not learned yet" : "–"
    V["cover"].Text := d ? Round(d.cover * 100) "%" : "–"
    V["rate"].Text := (Running && LiveRate) ? LiveRate " scans a second" : "–"
    V["mode"].Text := src.mode
}

LiveLogChanged() {
    if (!UiReady || CurTab != "Live")
        return
    s := ""
    for i, l in VisionLog {
        if (i > 4)
            break
        s .= (s = "" ? "" : "`n") l
    }
    try UI.liveLog.Text := s = "" ? "Nothing yet. New looks, relearning and ended reels are noted here." : s
}

; Saves the raw reel band, the annotated view and a text report.
SaveLiveSnapshot() {
    src := LiveSource()
    if !src
        return SetDetail("Nothing to save. Start fishing, or turn on Preview with the reel on screen.")
    b := src.b, d := src.d, p := src.p
    dir := A_ScriptDir "\Snapshots"
    try DirCreate(dir)
    stamp := FormatTime(, "yyyy-MM-dd_HH-mm-ss")
    DllCall("SelectObject", "Ptr", b.dc, "Ptr", b.old)
    ok := SavePng(b.bmp, dir "\" stamp "_band.png")
    DllCall("SelectObject", "Ptr", b.dc, "Ptr", b.bmp)
    hbm := VisionPicture(b, d, Max(200, b.w), Max(60, b.h * 2 + 14), false)
    SavePng(hbm, dir "\" stamp "_view.png")
    DllCall("DeleteObject", "Ptr", hbm)
    r := APP_NAME " " APP_VER " snapshot " stamp "`n`n"
    r .= "Mode: " src.mode "`nBand: " b.w " x " b.h " px`nReel box: " Format("{:.4f} {:.4f} {:.4f} {:.4f}", Cfg["ReelX1"], Cfg["ReelY1"], Cfg["ReelX2"], Cfg["ReelY2"]) "`n"
    if IsObject(p)
        r .= "`nLook: " p.name " (" p.id ")" (p.lib != "" ? ", library " p.lib : "") "`nBar width: " p.barW "`nTrack: " HexJoin(p.track) "`nBar: " HexJoin(p.bar) "`nFish: " HexJoin(p.fish) "`nEdges: " p.edgeT " / " p.edgeB "`nReels: " p.reels "`n"
    if IsObject(d)
        r .= "`nScan: bar " d.bar " (" d.bl "-" d.br "), fish " d.fish " (" Round(d.fx) (d.fishCol ? ", by colour" : ", by contrast") "), colours fit " Round(d.cover * 100) "%`n"
    r .= "`nLooks known: " RodProfiles.Length "`n`nDetection log:`n"
    for l in VisionLog
        r .= "  " l "`n"
    try FileAppend(r, dir "\" stamp "_report.txt", "UTF-8")
    SetDetail(ok ? "Saved snapshot " stamp " to the Snapshots folder." : "Couldn't save the snapshot picture.")
    LogVision("Snapshot saved: " stamp)
}

OpenSnapshots() {
    dir := A_ScriptDir "\Snapshots"
    try DirCreate(dir)
    try Run(dir)
}

;------------------------------------------------------------------------------
; The small panel in the top-right corner while fishing: what's happening,
; a mini gauge, catches, time and the rod, and a Stop button. It never takes
; focus from Roblox (WS_EX_NOACTIVATE) and can be dragged anywhere.
;------------------------------------------------------------------------------
class Hud {
    static g := 0, t := 0, d := 0, s := 0, stop := 0, gF := 0, gL := 0, gB := 0, gR := 0, W := 284, gw := 256, lastG := 0, live := -1
    static Build() {
        g := Gui("-Caption +AlwaysOnTop +ToolWindow +E0x08000000", APP_NAME " panel")
        g.BackColor := Pal.strip
        g.MarginX := 0, g.MarginY := 0
        A(x, y, w, h, text, role, size, color, bg, extra := "") {
            SetFontFor(g, "norm s" FZ(size) " c" color, role)
            return g.Add("Text", Format("x{} y{} w{} h{} Background{} {}", ZS(x), ZS(y), ZS(w), ZS(h), bg, extra), text)
        }
        W := this.W
        A(0, 0, 3, 112, "", "body", 9, Pal.text, Pal.accent)
        A(14, 8, 150, 16, "FISCHXR", "body", 8, Pal.dim, Pal.strip, "0x200")
        this.stop := A(W - 84, 6, 74, 22, "■  Stop", "body", 9, Pal.text, Pal.field, "Center 0x200")
        this.t := A(14, 26, W - 24, 24, "", "display", 12, Pal.text, Pal.strip, "0x200 0x4000")
        this.d := A(14, 50, W - 24, 18, "", "body", 9, Pal.dim, Pal.strip, "0x200 0x4000")
        this.gF := A(14, 70, 3, 4, "", "body", 9, Pal.text, Pal.faint)
        this.gL := A(14, 75, 10, 8, "", "body", 9, Pal.text, Pal.field)
        this.gB := A(24, 75, 10, 8, "", "body", 9, Pal.text, Pal.faint)
        this.gR := A(34, 75, 10, 8, "", "body", 9, Pal.text, Pal.field)
        this.s := A(14, 88, W - 24, 18, "", "body", 9, Pal.dim, Pal.strip, "0x200 0x4000")
        this.g := g, this.live := -1
        g.Show(Format("w{} h{} Hide", ZS(W), ZS(112)))
    }
    static Show() {
        if (this.g && this.g.BackColor != Pal.strip)
            this.Destroy()                     ; the theme changed
        if !this.g
            this.Build()
        this.Update()
        MonitorGetWorkArea(HudMonitor(), &L, &T, &R, &B)
        pw := Round(ZS(this.W) * A_ScreenDPI / 96)
        x := R - pw - 16, y := T + Round((B - T) * 0.06)
        if Cfg["ReduceMotion"] {
            this.g.Show(Format("x{} y{} NoActivate", x, y))
            return
        }
        this.g.Show(Format("x{} y{} NoActivate", x + 60, y))    ; slide in from the edge
        for k in [36, 18, 8, 3, 0] {
            Sleep 14
            try WinMove(x + k, y, , , "ahk_id " this.g.Hwnd)
        }
    }
    static Hide() {
        if this.g
            this.g.Hide()
    }
    static Destroy() {
        if this.g
            try this.g.Destroy()
        this.g := 0
    }
    static Visible() => this.g && DllCall("IsWindowVisible", "Ptr", this.g.Hwnd)
    static Update() {
        if !this.Visible()
            return
        try {
            this.t.Text := Phase.title
            this.t.SetFont("c" PhaseColor(Phase.kind))
            this.d.Text := Phase.detail
            secs := Stats.start ? (A_TickCount - Stats.start) // 1000 : 0
            this.s.Text := Format("{} casts  ·  {} reels  ·  {}:{:02}:{:02}{}", Stats.casts, Stats.reels
                , secs // 3600, Mod(secs // 60, 60), Mod(secs, 60), IsObject(CurRod) ? "  ·  " CurRod.name : "")
        }
    }
    static Gauge(l, r, f, live) {
        if (!this.Visible() || A_TickCount - this.lastG < 80)
            return
        this.lastG := A_TickCount
        try {
            w := ZS(this.gw), x0 := ZS(14)
            bl := Round(Clamp(l, 0, 1) * w), br := Round(Clamp(r, 0, 1) * w)
            if (br - bl < 2)
                br := Min(w, bl + 2), bl := br - 2
            this.gL.Move(x0, , bl), this.gB.Move(x0 + bl, , br - bl), this.gR.Move(x0 + br, , w - br)
            this.gF.Move(x0 + Round(Clamp(f, 0, 1) * (w - 3)))
            if (live != this.live) {
                this.live := live
                this.gB.Opt("Background" (live ? Pal.accent : Pal.faint)), this.gF.Opt("Background" (live ? Pal.text : Pal.faint))
                this.gB.Redraw(), this.gF.Redraw()
            }
        }
    }
    ; Where the panel is on screen (for checks that must look past it), or 0.
    static Rect() {
        if !this.Visible()
            return 0
        WinGetPos(&x, &y, &w, &h, "ahk_id " this.g.Hwnd)
        return {x: x, y: y, w: w, h: h}
    }
}

; The monitor Roblox is on, else the primary one.
HudMonitor() {
    try {
        if (RobloxHwnd && WinExist("ahk_id " RobloxHwnd)) {
            WinGetPos(&x, &y, &w, &h, "ahk_id " RobloxHwnd)
            cx := x + w // 2, cy := y + h // 2
            Loop MonitorGetCount() {
                MonitorGet(A_Index, &l, &t, &r, &b)
                if (cx >= l && cx < r && cy >= t && cy < b)
                    return A_Index
            }
        }
    }
    return MonitorGetPrimary()
}

; Fishing started: swap the window for the small panel (if that's on).
HudEnter() {
    if !Cfg["MiniHud"]
        return
    Hud.Show()
    if (UiReady && IsObject(MainGui) && DllCall("IsWindowVisible", "Ptr", MainGui.Hwnd)) {
        SaveGeometry()
        MainGui.Hide()
        UI.hiddenForHud := true
    }
}

; Fishing stopped: the panel goes, the window comes back.
HudLeave() {
    Hud.Hide()
    if (UiReady && IsObject(MainGui) && UI.hiddenForHud) {
        UI.hiddenForHud := false
        MainGui.Show()
        Layout()
    }
}

SelectRod(i, *) => 0

; A short slide as a page appears: its controls ease in from the right.
; Skipped with Reduce motion, and before the window is on screen.
SlideIn(ctls) {
    if (Cfg["ReduceMotion"] || !UiReady || !IsObject(MainGui) || !DllCall("IsWindowVisible", "Ptr", MainGui.Hwnd))
        return
    pos := []
    for c in ctls {
        c.GetPos(&x, &y)
        pos.Push([c, x])
    }
    for k in [18, 10, 5, 2, 0] {
        for it in pos
            it[1].Move(it[2] + ZS(k))
        Sleep 12
    }
}


;==============================================================================
; Settings actions
;==============================================================================
StepSetting(key, dir, mult := 1, *) {
    if (key = "Zoom")
        return ZoomStep(dir)
    sp := NumSpec[key]
    v := Clamp(Cfg[key] + dir * sp.step * mult, sp.min, sp.max)
    if (v = Cfg[key])
        return
    Cfg[key] := v
    try Steppers[key].Text := StepText(key)
    try UI.units[key].Text := StepUnit(key)
    Save(key)
    switch key {
        case "AqEvery": RefreshRobloxInfo()
        case "Predict", "Latency": RodsChanged()
        case "NightLevel", "TotemWait": TotemsChanged()
        case "SovEvery", "SovCount": PaintSovStatus()
        case "HookSummary":
            if Running
                SetTimer(SummaryTick, v ? v * 60000 : 0)
    }
}

RepeatStep() {
    if (!GetKeyState("LButton", "P") || ChildAtCursor() != Repeat.hwnd)
        return
    Repeat.n++
    StepSetting(Repeat.key, Repeat.dir, Repeat.n > 10 ? 5 : 1)
    SetTimer(RepeatStep, -60)
}

FlipToggle(key, *) {
    SetToggle(key, !Cfg[key])
}

ToggleAdj(key, dir, *) {
    SetToggle(key, dir > 0)
}

SetToggle(key, on, *) {
    on := on ? 1 : 0
    if (Cfg[key] = on)
        return
    Cfg[key] := on
    Save(key)
    PaintToggle(key)
    switch key {
        case "OnTop":
            try WinSetAlwaysOnTop(on, "ahk_id " MainGui.Hwnd)
        case "ShowAreas":
            if on {
                UpdateOverlay()
                SetTimer(UpdateOverlay, 500)
            } else {
                SetTimer(UpdateOverlay, 0)
                HideOverlay()
            }
        case "ColorSafe":
            SetTimer(RebuildGui, -1)
        case "AqAuto":
            RefreshRobloxInfo()
        case "TotemAuto":
            TotemsChanged()
        case "SovAuto":
            PaintSovStatus()
        case "AutoReconnect":
            if Running
                SetTimer(WatchConnection, on ? 3000 : 0)
    }
    Say(on ? "on" : "off")
}

CycleChoice(key, dir, *) {
    opts := []
    if Choices.Has(key)
        opts := Choices[key].options
    else if SegCtls.Has(key)
        for s in SegCtls[key]
            opts.Push([s.value, s.text])
    if !opts.Length
        return
    idx := 1
    for i, o in opts
        if (o[1] = Cfg[key])
            idx := i
    SetChoiceValue(key, opts[Mod(idx - 1 + dir + opts.Length, opts.Length) + 1][1])
}

SetChoiceValue(key, value, *) {
    if (Cfg[key] = value)
        return
    Cfg[key] := value
    Save(key)
    PaintSegs(key), PaintChoice(key)
    if (key = "Theme") {
        SetTimer(RebuildGui, -1)
    } else if (key = "ControlStyle") {
        RodsChanged()
    }
    Say(ChoiceText(key))
}

SpokenValue(key, *) {
    if NumSpec.Has(key)
        return (StepText(key) = "Auto" || StepText(key) = "Off") ? StepText(key) : Cfg[key] " " UnitWord(NumSpec[key].unit)
    if KeyBtns.Has(key)
        return Cfg[key] = "" ? "not set" : KeyName(Cfg[key])
    if Toggles.Has(key)
        return Cfg[key] ? "on" : "off"
    return ChoiceText(key)
}

UnitWord(u) {
    static words := Map("ms", "milliseconds", "s", "seconds", "%", "percent", "min", "minutes", "reels", "reels")
    return words.Has(u) ? words[u] : ""
}

ZoomStep(dir, *) {
    cur := Cfg["Zoom"], nxt := cur
    if (dir > 0) {
        for z in ZoomSteps {
            if (z > cur) {
                nxt := z
                break
            }
        }
    } else {
        Loop ZoomSteps.Length {
            z := ZoomSteps[ZoomSteps.Length - A_Index + 1]
            if (z < cur) {
                nxt := z
                break
            }
        }
    }
    SetZoom(nxt)
}

SetZoom(pct, *) {
    pct := Clamp(pct, 80, 200)
    if (pct = Cfg["Zoom"])
        return
    Cfg["Zoom"] := pct
    Save("Zoom")
    try Steppers["Zoom"].Text := pct
    try UI.sbZoom.Text := pct "%"
    Say("Zoom " pct " percent")
    SetTimer(RebuildGui, -300)
}

CaptureKeyFor(key, *) {
    global Capturing
    if (Capturing || Calibrating)
        return
    ti := RegExMatch(key, "^Totem:(\d+)$", &tm) ? Integer(tm[1]) : 0
    if (ti && ti > Totems.Length)
        return
    if Running
        StopMacro()
    Capturing := true
    b := ti ? UI.totemRows[ti].key : KeyBtns[key]
    b.Text := "Press a key"
    b.SetFont("c" Pal.wait)
    Say("Press a key")
    Suspend(true)
    ih := InputHook("L0 T8")
    ih.KeyOpt("{All}", "ES")
    ih.KeyOpt("{LCtrl}{RCtrl}{LAlt}{RAlt}{LShift}{RShift}{LWin}{RWin}", "-ES")
    ih.Start()
    ih.Wait()
    Suspend(false)
    k := (ih.EndReason = "EndKey") ? ih.EndKey : ""
    note := ""
    if (ti && k != "" && k != "Escape") {
        problem := KeyProblem(key, k)
        if (problem != "")
            note := problem
        else
            Totems[ti].slot := k, SaveTotems()
    } else if (k != "" && k != "Escape") {
        problem := KeyProblem(key, k)
        if (problem != "") {
            note := problem
        } else {
            old := Cfg[key]
            Cfg[key] := k
            if ((key = "ToggleKey" || key = "ExitKey") && !BindHotkeys()) {
                Cfg[key] := old
                BindHotkeys()
                note := KeyName(k) " can't be used as a hotkey."
            } else {
                Save(key)
            }
        }
    }
    try {
        if ti
            TotemsChanged()
        else
            b.Text := Cfg[key] = "" ? "Not set" : KeyName(Cfg[key]), b.SetFont("c" Pal.text)
    }
    Capturing := false
    UpdateStartControls()
    BuildMenus()
    if (note != "")
        SetPhase("error", "Key not changed", note)
    else
        SetPhase("idle", "Ready", IdleHint())
    Say(note != "" ? note : KeyName(Cfg[key]))
}

KeyProblem(target, k) {
    hot := (target = "ToggleKey" || target = "ExitKey")
    if (k = "Enter" || k = "NumpadEnter")
        return "Enter is used for shaking. Pick a different key."
    if (hot && RegExMatch(k, "i)^(Tab|Space|Escape|Up|Down|Left|Right|Backspace|Delete)$"))
        return KeyName(k) " is needed for normal typing and moving around. Pick a function key instead."
    uses := Map("ToggleKey", "start and stop", "ExitKey", "quit", "NavKey", "UI navigation", "RodKey", "the rod slot"
        , "SovInvKey", "the inventory")
    for name, what in uses {
        if (name = target || Cfg[name] != k)
            continue
        if (hot || name = "ToggleKey" || name = "ExitKey" || (SubStr(target, 1, 6) = "Totem:" && name = "RodKey"))
            return KeyName(k) " is already set for " what "."
    }
    return ""
}

BindHotkeys() {
    static bound := Map()
    ok := true
    for name, fn in Map("ToggleKey", HK_Toggle, "ExitKey", HK_Quit) {
        if bound.Has(name)
            try Hotkey(bound[name], "Off")
        try {
            Hotkey(Cfg[name], fn, "On")
            bound[name] := Cfg[name]
        } catch {
            ok := false
        }
    }
    return ok
}

HK_Toggle(*) => ToggleMacro()
HK_Quit(*) => ExitApp()

ConfirmReset() {
    Dialog.Show("Reset all settings?", "This deletes FischMacro.ini, including your rod looks, totem schedule and alert settings, then restarts it.", "Reset", DoReset, "Cancel")
}

DoReset(*) {
    global NoSave
    if Running
        StopMacro()
    NoSave := true
    try FileDelete(IniPath)
    Reload()
}

ShowShortcuts() {
    Dialog.Show("Keyboard shortcuts"
        , "Tab and Shift+Tab move between controls.`nArrow keys change the focused value.`nSpace or Enter activates it.`n"
        . "Ctrl+Tab and Ctrl+Shift+Tab switch tabs. Ctrl+1 to Ctrl+8 jump to the main tabs.`n"
        . "In a text field, Enter finishes and Esc cancels.`n"
        . "Ctrl+plus, Ctrl+minus and Ctrl+0 zoom. Ctrl+mouse wheel zooms too.`n"
        . "Alt+F, Alt+M, Alt+V and Alt+H open the menus.`n"
        . KeyName(Cfg["ToggleKey"]) " starts and stops fishing from any window. " KeyName(Cfg["ExitKey"]) " quits.")
}

ShowAbout() {
    Dialog.Show("About " APP_NAME
        , APP_NAME " " APP_VER " on AutoHotkey " A_AhkVersion ".`n"
        . "It reads the screen and presses keys. It never touches game memory.`n"
        . "Rod skins are learned by watching which block moves with the bar.`n"
        . "Library rod colors and the aquarium panel layout come from DeepFish v1.0.3.`n"
        . "Macros break Roblox's terms of use, and unattended farming is what gets accounts banned.")
}

RefreshRobloxInfo(*) {
    global RobloxInfo
    UsePhysicalPixels()
    h := FindRoblox()
    cr := h ? ClientRect(h) : 0
    RobloxInfo := {found: h != 0, w: cr ? cr.w : 0, h: cr ? cr.h : 0}
    if !UiReady
        return
    try {
        if h {
            UI.hRbx.Text := cr ? Format("Roblox found, {} × {}", cr.w, cr.h) : "Roblox found, but its window is minimized"
            UI.iRbx.Text := cr ? Format("{} × {}", cr.w, cr.h) : "Minimized"
            col := Pal.accent
        } else {
            UI.hRbx.Text := "Roblox isn't open yet"
            UI.iRbx.Text := "Not found"
            col := Pal.wait
        }
        UI.hDot.SetFont("c" col)
        UI.iAq.Text := NextJobText()
    }
}

;==============================================================================
; Mouse. Text controls are transparent to the mouse, so the window receives
; the messages and the control under the cursor is looked up by position.
;==============================================================================
WM_LBUTTONDOWN(wParam, lParam, msg, hwnd) {
    x := lParam & 0xFFFF, y := (lParam >> 16) & 0xFFFF
    x := x >= 0x8000 ? x - 0x10000 : x, y := y >= 0x8000 ? y - 0x10000 : y
    if (IsObject(Dialog.g) && hwnd = Dialog.g.Hwnd) {
        h := ChildAt(hwnd, x, y)
        if (h && Clickables.Has(h)) {
            Press(h, Clickables[h])
            return 0
        }
        PostMessage(0xA1, 2, 0, , "ahk_id " hwnd)
        return 0
    }
    ; the small panel while fishing: Stop, or drag it anywhere
    if (Hud.g && hwnd = Hud.g.Hwnd) {
        if (ChildAt(hwnd, x, y) = Hud.stop.Hwnd)
            SetTimer(ToggleMacro, -1)
        else
            PostMessage(0xA1, 2, 0, , "ahk_id " hwnd)
        return 0
    }
    if (!IsObject(MainGui) || hwnd != MainGui.Hwnd || !UiReady)
        return
    zone := ResizeZone(x, y)
    if (zone != "") {
        SetTimer(ResizeLoop.Bind(zone), -1)
        return 0
    }
    if FocusOn
        FocusClear()
    h := ChildAt(hwnd, x, y)
    if (h && Clickables.Has(h)) {
        Press(h, Clickables[h])
        return 0
    }
    if (msg = 0x203 && y < ToPhys(TAB_H)) {
        SetTimer(ToggleMaximize, -1)
        return 0
    }
    if !Maxed
        PostMessage(0xA1, 2, 0, , "ahk_id " hwnd)   ; drag the window
}

Press(h, e) {
    switch e.kind {
        case "btn", "dlg":
            if e.fn
                SetTimer(e.fn, -1)
        case "step":
            StepSetting(e.key, e.dir)
            Repeat.key := e.key, Repeat.dir := e.dir, Repeat.hwnd := h, Repeat.n := 0
            SetTimer(RepeatStep, -380)
        case "toggle":
            FlipToggle(e.key)
        case "seg":
            SetChoiceValue(e.key, e.value)
        case "tab":
            NavPress(e.name)
        case "key":
            SetTimer(CaptureKeyFor.Bind(e.key), -1)
        case "menu":
            SetTimer(OpenMenu.Bind(e.name), -1)
        case "choice":
            SetTimer(OpenChoiceMenu.Bind(e.key), -1)
        case "sbmenu":
            SetTimer(OpenMenu.Bind(e.menu, e.obj), -1)
        case "rodsel":
            SelectRod(e.i)
        case "tt":
            TotemOp(e.op, e.i)
    }
}

WM_MOUSEMOVE(wParam, lParam, msg, hwnd) {
    if (!IsObject(MainGui) || hwnd != MainGui.Hwnd || !UiReady)
        return
    x := lParam & 0xFFFF, y := (lParam >> 16) & 0xFFFF
    h := ChildAt(hwnd, x >= 0x8000 ? x - 0x10000 : x, y >= 0x8000 ? y - 0x10000 : y)
    SetHover(h)
    if !FocusOn
        ShowDesc(h && DescOf.Has(h) ? DescOf[h] : "")
}

WM_MOUSEWHEEL(wParam, lParam, msg, hwnd) {
    if (!IsObject(MainGui) || !UiReady)
        return
    dir := ((wParam >> 16) & 0xFFFF) >= 0x8000 ? -1 : 1
    if (GetKeyState("Ctrl") && WinActive("ahk_id " MainGui.Hwnd)) {
        ZoomStep(dir)
        return 0
    }
    h := ChildAtCursor()
    if !(h && Clickables.Has(h))
        return
    e := Clickables[h]
    if (e.HasOwnProp("key") && NumSpec.Has(e.key)) {
        StepSetting(e.key, dir)
        return 0
    }
}

WM_SETCURSOR(wParam, lParam, msg, hwnd) {
    if (FreezeHwnd && DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr") = FreezeHwnd) {
        DllCall("SetCursor", "Ptr", DllCall("LoadCursor", "Ptr", 0, "Ptr", 32515, "Ptr"))
        return true
    }
    if (IsObject(MainGui) && UiReady && hwnd = MainGui.Hwnd && !Maxed) {
        pt := CursorClient()
        zone := ResizeZone(pt.x, pt.y)
        if (zone != "") {
            id := (zone = "rb") ? 32642 : (zone = "r") ? 32644 : 32645
            DllCall("SetCursor", "Ptr", DllCall("LoadCursor", "Ptr", 0, "Ptr", id, "Ptr"))
            return true
        }
    }
}

; Paints the Notepad-style bands behind the controls.
WM_ERASEBKGND(wParam, lParam, msg, hwnd) {
    if (!IsObject(MainGui) || hwnd != MainGui.Hwnd)
        return
    rc := Buffer(16, 0)
    DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rc)
    W := NumGet(rc, 8, "Int"), H := NumGet(rc, 12, "Int")
    sw := ToPhys(SIDEBAR_W), s := ToPhys(STATUS_H), one := Max(1, ToPhys(1))
    FillBand(wParam, 0, 0, sw, H, Pal.strip)                            ; sidebar
    FillBand(wParam, sw, 0, sw + one, H, Pal.seam)
    FillBand(wParam, sw + one, 0, W, H - s - one, Pal.content)          ; page
    FillBand(wParam, sw + one, H - s - one, W, H - s, Pal.seam)
    FillBand(wParam, sw + one, H - s, W, H, Pal.bar)                    ; status line
    return 1
}

ResizeZone(x, y) {
    if (Maxed || !IsObject(MainGui))
        return ""
    rc := Buffer(16, 0)
    DllCall("GetClientRect", "Ptr", MainGui.Hwnd, "Ptr", rc)
    W := NumGet(rc, 8, "Int"), H := NumGet(rc, 12, "Int")
    c := ToPhys(14), e := Max(4, ToPhys(5))
    if (x >= W - c && y >= H - c)
        return "rb"
    if (x >= W - e && y > ToPhys(TAB_H))
        return "r"
    if (y >= H - e)
        return "b"
    return ""
}

SetHover(h) {
    global Hover
    if (h = Hover)
        return
    same := h && Hover && Clickables.Has(h) && Clickables.Has(Hover) && Clickables[h] = Clickables[Hover]
    if (!same && Hover)
        Paint(Hover, false)
    Hover := h
    if (!same && h && Clickables.Has(h) && Clickables[h].HasOwnProp("hv")) {
        Paint(h, true)
        SetTimer(HoverWatch, 60)
    }
}

HoverWatch() {
    h := ChildAtCursor()
    if (h != Hover)
        SetHover(h)
    if !Hover
        SetTimer(HoverWatch, 0)
}

Paint(h, hot) {
    if !Clickables.Has(h)
        return
    e := Clickables[h]
    if !e.HasOwnProp("hv")
        return
    for c in (e.HasOwnProp("objs") ? e.objs : [e.obj]) {
        try {
            c.Opt("Background" (hot ? e.hv : e.bg))
            if (e.HasOwnProp("hvText") && e.hvText != "")
                c.SetFont("c" (hot ? e.hvText : Pal.text))
            c.Redraw()
        }
    }
}

ShowDesc(text) {
    if !UiReady
        return
    want := text != "" ? text : Pages[CurTab].desc
    try {
        if (UI.desc.Text != want)
            UI.desc.Text := want
    }
}

CursorClient() {
    pt := Buffer(8, 0)
    DllCall("GetCursorPos", "Ptr", pt)
    DllCall("ScreenToClient", "Ptr", MainGui.Hwnd, "Ptr", pt)
    return {x: NumGet(pt, 0, "Int"), y: NumGet(pt, 4, "Int")}
}

ChildAtCursor() {
    if !IsObject(MainGui)
        return 0
    pt := Buffer(8, 0)
    DllCall("GetCursorPos", "Ptr", pt)
    top := DllCall("WindowFromPoint", "Int64", NumGet(pt, 0, "Int64"), "Ptr")
    if (top != MainGui.Hwnd && DllCall("GetAncestor", "Ptr", top, "UInt", 1, "Ptr") != MainGui.Hwnd)
        return 0
    DllCall("ScreenToClient", "Ptr", MainGui.Hwnd, "Ptr", pt)
    return ChildAt(MainGui.Hwnd, NumGet(pt, 0, "Int"), NumGet(pt, 4, "Int"))
}

ChildAt(parent, x, y) {
    h := DllCall("ChildWindowFromPointEx", "Ptr", parent, "Int64", (y << 32) | (x & 0xFFFFFFFF), "UInt", 1, "Ptr")
    return (h = parent) ? 0 : h
}

;==============================================================================
; Keyboard: a focus ring that walks the toolbar and the current page.
;==============================================================================
FocusList() {
    list := []
    for it in FocusGlobal
        if (!it.HasOwnProp("navMode") || it.navMode = UI.navMode)   ; skip the hidden sidebar set
            list.Push(it)
    for it in Pages[CurTab].focus
        list.Push(it)
    return list
}

FocusMove(dir) {
    global FocusIdx, FocusOn
    list := FocusList()
    if !list.Length
        return
    if !FocusOn {
        FocusOn := true
        nGlobal := 0                     ; the sidebar items in the list (the hidden set is skipped)
        for it in FocusGlobal
            nGlobal += (!it.HasOwnProp("navMode") || it.navMode = UI.navMode)
        FocusIdx := dir > 0 ? Min(nGlobal + 1, list.Length) : list.Length
    } else {
        FocusIdx := Mod(FocusIdx - 1 + dir + list.Length, list.Length) + 1
    }
    ShowFocus(list[FocusIdx])
}

ShowFocus(item, speak := true) {
    x1 := 99999, y1 := 99999, x2 := -99999, y2 := -99999
    for c in item.ctls {
        c.GetPos(&cx, &cy, &cw, &ch)
        x1 := Min(x1, cx), y1 := Min(y1, cy), x2 := Max(x2, cx + cw), y2 := Max(y2, cy + ch)
    }
    o := ZS(3), t := Max(2, ZS(Pal.ring)), r := UI.ring
    r[1].Move(x1 - o - t, y1 - o - t, x2 - x1 + 2 * (o + t), t)
    r[2].Move(x1 - o - t, y2 + o, x2 - x1 + 2 * (o + t), t)
    r[3].Move(x1 - o - t, y1 - o, t, y2 - y1 + 2 * o)
    r[4].Move(x2 + o, y1 - o, t, y2 - y1 + 2 * o)
    for c in r {
        c.Visible := true
        c.Redraw()
    }
    if (item.desc != "")
        ShowDesc(item.desc)
    if speak
        Say(item.name (item.value ? ", " item.value.Call() : ""))
}

HideRing() {
    if UI.HasOwnProp("ring")
        for c in UI.ring
            try c.Visible := false
}

FocusActivate() {
    list := FocusList()
    if (!FocusOn || FocusIdx < 1 || FocusIdx > list.Length)
        return FocusMove(1)
    it := list[FocusIdx]
    if it.act
        it.act.Call()
    else if it.adj
        it.adj.Call(1)
    AfterFocusChange(it)
}

FocusAdjust(dir) {
    list := FocusList()
    if (!FocusOn || FocusIdx < 1 || FocusIdx > list.Length)
        return
    it := list[FocusIdx]
    if it.adj {
        it.adj.Call(dir)
        AfterFocusChange(it)
    }
}

AfterFocusChange(it) {
    if (!FocusOn || !UiReady)
        return
    list := FocusList()
    if (FocusIdx <= list.Length)
        try ShowFocus(list[FocusIdx], false)
    if it.value
        try Say(it.value.Call())
}

FocusClear() {
    global FocusOn
    FocusOn := false
    HideRing()
    ShowDesc("")
}

; Keyboard for this window. Keys arrive as ordinary key messages while the
; window has focus, so no global keyboard hook is installed and nothing
; reacts while another window is in front. Returning 0 marks a key handled.
WM_KEYDOWN(wParam, lParam, msg, hwnd) {
    top := DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr")
    rep := (lParam >> 30) & 1
    if (IsObject(Dialog.g) && top = Dialog.g.Hwnd)
        return DialogKey(wParam, rep)
    if (!IsObject(MainGui) || top != MainGui.Hwnd || !UiReady || Capturing || Calibrating || MenuOpen)
        return
    if EditCtls.Has(hwnd)
        return EditKey(EditCtls[hwnd], wParam, msg = 0x104)
    return PanelKey(wParam, msg = 0x104, rep)
}

; In a text field every key types, except Tab (moves on), Enter (done) and
; Esc (cancel), plus the Alt menus.
EditKey(ed, vk, alt) {
    if alt
        return PanelKey(vk, true, 0)
    switch vk {
        case 0x09:
            try MainGui.Focus()
            FocusMove(GetKeyState("Shift") ? -1 : 1)
            return 0
        case 0x0D:
            if (ed.key = "rename")
                CommitRename(true)
            else
                try MainGui.Focus()
            return 0
        case 0x1B:
            if (ed.key = "rename")
                CommitRename(false)
            else
                try MainGui.Focus()
            return 0
    }
}

; A lone Alt tap would put the window into system-menu mode and swallow the
; next key, so the release is consumed.
WM_SYSKEYUP(wParam, lParam, msg, hwnd) {
    if (wParam = 0x12 && IsObject(MainGui) && DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr") = MainGui.Hwnd)
        return 0
}

DialogKey(vk, rep) {
    if (vk = 0x0D || vk = 0x20) {
        if !rep
            SetTimer(ObjBindMethod(Dialog, "Ok"), -1)
        return 0
    }
    if (vk = 0x1B) {
        Dialog.Close()
        return 0
    }
}

PanelKey(vk, alt, rep) {
    ; Tab and the arrow keys repeat while held; everything else acts once.
    repeats := (vk = 0x09 || (vk >= 0x25 && vk <= 0x28))
    if (rep && !repeats) {
        if (alt || vk = 0x0D || vk = 0x20 || vk = 0x1B || GetKeyState("Ctrl"))
            return 0
        return
    }
    if alt {
        switch vk {
            case 0x46: SetTimer(OpenMenu.Bind("File"), -1)
            case 0x4D: SetTimer(OpenMenu.Bind("Macro"), -1)
            case 0x56: SetTimer(OpenMenu.Bind("View"), -1)
            case 0x48: SetTimer(OpenMenu.Bind("Help"), -1)
            case 0x79: SetTimer(OpenMenu.Bind("File"), -1)
            default: return
        }
        return 0
    }
    shift := GetKeyState("Shift")
    if GetKeyState("Ctrl") {
        switch vk {
            case 0x09: CycleTab(shift ? -1 : 1)
            case 0x22: CycleTab(1)
            case 0x21: CycleTab(-1)
            case 0xBB, 0x6B: ZoomStep(1)
            case 0xBD, 0x6D: ZoomStep(-1)
            case 0x30, 0x60: SetZoom(100)
            case 0x53:
                FlushSaves()
                SetDetail("Settings saved.")
            default:
                if (vk >= 0x31 && vk <= 0x30 + BasicTabs.Length)
                    SwitchTab(BasicTabs[vk - 0x30])
                else
                    return
        }
        return 0
    }
    switch vk {
        case 0x09: FocusMove(shift ? -1 : 1)
        case 0x28: FocusMove(1)
        case 0x26: FocusMove(-1)
        case 0x25: FocusAdjust(-1)
        case 0x27: FocusAdjust(1)
        case 0x20, 0x0D: FocusActivate()
        case 0x1B: FocusClear()
        case 0x79: SetTimer(OpenMenu.Bind("File"), -1)
        default: return
    }
    return 0
}

;==============================================================================
; Menus. Popup menus follow the theme through uxtheme's app dark mode.
;==============================================================================
BuildMenus() {
    global Menus, StartItemName
    Menus := Map()
    ApplyMenuTheme()
    f := Menu()
    f.Add("Save settings now`tCtrl+S", (*) => (FlushSaves(), SetDetail("Settings saved.")))
    f.Add("Open settings folder", (*) => OpenSettingsFolder())
    f.Add()
    f.Add("Reset all settings…", (*) => ConfirmReset())
    f.Add()
    f.Add("Exit`t" KeyName(Cfg["ExitKey"]), (*) => ExitApp())
    Menus["File"] := f
    style := Menu()
    style.Add("Physics, learns your rod", SetChoiceValue.Bind("ControlStyle", "physics"))
    style.Add("Simple look-ahead", SetChoiceValue.Bind("ControlStyle", "simple"))
    Menus["Style"] := style
    m := Menu()
    StartItemName := "Start fishing`t" KeyName(Cfg["ToggleKey"])
    m.Add(StartItemName, (*) => ToggleMacro())
    m.Add("Run aquarium now", (*) => RunAquariumNow())
    m.Add("Use totems now", (*) => SetTimer(UseTotemsNow, -1))
    m.Add("Recharge Sovereign now", (*) => SetTimer(RechargeNow, -1))
    m.Add()
    m.Add("Set reel area and teach a look…", (*) => StartCalibrate("Reel"))
    m.Add("Set shake area…", (*) => StartCalibrate("Shake"))
    m.Add()
    m.Add("Control style", style)
    Menus["Macro"] := m
    th := Menu()
    for t in ["Black", "Dark", "Light", "High contrast"]
        th.Add(t, SetChoiceValue.Bind("Theme", t))
    Menus["Theme"] := th
    zm := Menu()
    for z in ZoomSteps
        zm.Add(z "%", SetZoom.Bind(z))
    Menus["Zoom"] := zm
    tabs := Menu()
    for i, t in TabNames
        tabs.Add(t "`tCtrl+" i, GoTab.Bind(t))
    Menus["Tabs"] := tabs
    v := Menu()
    v.Add("Go to tab", tabs)
    v.Add()
    v.Add("Theme", th)
    v.Add("Zoom", zm)
    v.Add("Zoom in`tCtrl+Plus", (*) => ZoomStep(1))
    v.Add("Zoom out`tCtrl+Minus", (*) => ZoomStep(-1))
    v.Add("Reset zoom`tCtrl+0", (*) => SetZoom(100))
    v.Add()
    v.Add("Show scan areas", (*) => FlipToggle("ShowAreas"))
    v.Add("Keep window on top", (*) => FlipToggle("OnTop"))
    v.Add("Color-blind safe colors", (*) => FlipToggle("ColorSafe"))
    v.Add("Reduce motion", (*) => FlipToggle("ReduceMotion"))
    Menus["View"] := v
    hm := Menu()
    hm.Add("Start menu", (*) => SwitchTab("Home"))
    hm.Add("Keyboard shortcuts", (*) => ShowShortcuts())
    hm.Add()
    hm.Add("About " APP_NAME, (*) => ShowAbout())
    Menus["Help"] := hm
}

RefreshMenus() {
    global StartItemName
    try {
        for i, t in TabNames
            SetCheck(Menus["Tabs"], t "`tCtrl+" i, CurTab = t)
        SetCheck(Menus["Style"], "Physics, learns your rod", Cfg["ControlStyle"] = "physics")
        SetCheck(Menus["Style"], "Simple look-ahead", Cfg["ControlStyle"] = "simple")
        for t in ["Black", "Dark", "Light", "High contrast"]
            SetCheck(Menus["Theme"], t, Cfg["Theme"] = t)
        for z in ZoomSteps
            SetCheck(Menus["Zoom"], z "%", Cfg["Zoom"] = z)
        for pair in [["Show scan areas", "ShowAreas"], ["Keep window on top", "OnTop"], ["Color-blind safe colors", "ColorSafe"], ["Reduce motion", "ReduceMotion"]]
            SetCheck(Menus["View"], pair[1], Cfg[pair[2]])
        want := ((Running || AqManual) ? "Stop`t" : "Start fishing`t") KeyName(Cfg["ToggleKey"])
        if (want != StartItemName) {
            Menus["Macro"].Rename(StartItemName, want)
            StartItemName := want
        }
    }
}

GoTab(name, *) => SwitchTab(name)

SetCheck(m, item, on) {
    if on
        m.Check(item)
    else
        m.Uncheck(item)
}

OpenMenu(name, anchor := 0, *) {
    global MenuOpen
    if (!Menus.Has(name) || MenuOpen || !IsObject(MainGui))
        return
    if (!IsObject(anchor) && UI.menuBtns.Has(name))
        anchor := UI.menuBtns[name]
    RefreshMenus()
    if IsObject(anchor) {
        WinGetPos(&x, &y, &w, &h, "ahk_id " anchor.Hwnd)
        y += h
    } else {
        MouseGetPos(&x, &y)
    }
    MenuOpen := true
    try Menus[name].Show(x, y)
    MenuOpen := false
}

OpenChoiceMenu(key, *) {
    global MenuOpen
    if (MenuOpen || !Choices.Has(key))
        return
    ch := Choices[key]
    m := Menu()
    for o in ch.options {
        m.Add(o[2], SetChoiceValue.Bind(key, o[1]))
        if (Cfg[key] = o[1])
            m.Check(o[2])
    }
    WinGetPos(&x, &y, &w, &h, "ahk_id " ch.ctl.Hwnd)
    MenuOpen := true
    try m.Show(x, y + h)
    MenuOpen := false
}

ApplyMenuTheme() {
    static ux := DllCall("LoadLibrary", "Str", "uxtheme", "Ptr")
    if !ux
        return
    try {
        setMode := DllCall("GetProcAddress", "Ptr", ux, "Ptr", 135, "Ptr")
        flush := DllCall("GetProcAddress", "Ptr", ux, "Ptr", 136, "Ptr")
        if setMode
            DllCall(setMode, "Int", Pal.dark ? 2 : 3)
        if flush
            DllCall(flush)
    }
}

OpenSettingsFolder() {
    FlushSaves()
    if FileExist(IniPath)
        Run('explorer.exe /select,"' IniPath '"')
    else
        Run(A_ScriptDir)
}

; A small themed dialog owned by the main window.
class Dialog {
    static g := 0, okFn := 0
    static Show(title, body, okText := "Close", okFn := 0, cancelText := "") {
        this.Close()
        if !IsObject(MainGui)
            return
        g := Gui("-Caption +ToolWindow +Owner" MainGui.Hwnd (Cfg["OnTop"] ? " +AlwaysOnTop" : ""), title)
        g.BackColor := Pal.bar
        g.MarginX := 0, g.MarginY := 0
        w := 460
        SetFontFor(g, "norm s" FZ(14) " c" Pal.text, "display")
        g.Add("Text", Format("x{} y{} w{} Background{}", ZS(24), ZS(20), ZS(w - 48), Pal.bar), title)
        SetFontFor(g, "norm s" FZ(10) " c" Pal.text, "body")
        b := g.Add("Text", Format("x{} y{} w{} Background{}", ZS(24), ZS(58), ZS(w - 48), Pal.bar), body)
        b.GetPos(, &by, , &bh)
        y := by + bh + ZS(22), bw := ZS(120), bh2 := ZS(32)
        SetFontFor(g, "norm s" FZ(10) " c" Pal.ink, "body")
        ok := g.Add("Text", Format("x{} y{} w{} h{} Center 0x200 Background{}", ZS(w - 24 - 120), y, bw, bh2, Pal.accent), okText)
        Clickables[ok.Hwnd] := {kind: "dlg", fn: ObjBindMethod(Dialog, "Ok"), obj: ok}
        if (cancelText != "") {
            SetFontFor(g, "norm s" FZ(10) " c" Pal.text, "body")
            cn := g.Add("Text", Format("x{} y{} w{} h{} Center 0x200 Background{}", ZS(w - 24 - 252), y, bw, bh2, Pal.field), cancelText)
            Clickables[cn.Hwnd] := {kind: "dlg", fn: ObjBindMethod(Dialog, "Close"), obj: cn}
        }
        g.OnEvent("Escape", (*) => Dialog.Close())
        g.Show(Format("Hide w{} h{}", ZS(w), y + bh2 + ZS(22)))
        WinRect(g.Hwnd, &dx, &dy, &dw, &dh)
        WinGetPos(&mx, &my, &mw, &mh, "ahk_id " MainGui.Hwnd)
        g.Show(Format("x{} y{}", mx + (mw - dw) // 2, my + (mh - dh) // 3))
        StyleWindow(g.Hwnd)
        this.g := g, this.okFn := okFn
        Say(title ". " StrReplace(body, "`n", " "))
    }
    static Ok(*) {
        fn := this.okFn
        this.Close()
        if fn
            fn.Call()
    }
    static Close(*) {
        if this.g {
            try this.g.Destroy()
            this.g := 0
        }
    }
}

;==============================================================================
; Speech and sound cues
;==============================================================================
Say(text) {
    global Voice
    if (!Cfg["Speak"] || text = "")
        return
    try {
        if !IsObject(Voice)
            Voice := ComObject("SAPI.SpVoice")
        Voice.Speak(text, 3)      ; asynchronous, replacing anything still being spoken
    }
}

Cue(kind) {
    static sounds := Map("start", "*64", "catch", "*-1", "pause", "*48", "error", "*16")
    if Cfg["Sounds"]
        try SoundPlay(sounds.Has(kind) ? sounds[kind] : "*-1")
}

;==============================================================================
; Area setup: freeze the Roblox window, then drag a box, sample colours or
; click the aquarium button.
;==============================================================================
StartCalibrate(kind) {
    SetTimer(Calibrate.Bind(kind), -1)
}

Calibrate(kind) {
    global Calibrating, CalFlag, FreezeHwnd
    if (Calibrating || Capturing || AqManual)
        return
    if Running
        StopMacro()
    UsePhysicalPixels()
    hwnd := FindRoblox()
    if !hwnd {
        SetPhase("error", "Roblox isn't open", "Open Fisch first, then try again.")
        Cue("error")
        return
    }
    Calibrating := true
    CalFlag := ""
    HideOverlay()
    MainGui.Hide()
    try WinActivate("ahk_id " hwnd)
    Hotkey("*Esc", CalEsc, "On")
    Hotkey("*Enter", CalEnter, "On")
    fz := 0, sel := 0, hbm := 0, result := "cancel", what := ""
    try {
        if (kind = "Reel")
            Banner.Show("Hook a fish. When the reel bar is on screen, press Ctrl to freeze it.`nEsc cancels.", hwnd)
        else
            Banner.Show("Press Ctrl to freeze the screen.`nEsc cancels.", hwnd)
        if !WaitForCtrl()
            throw Error("cancelled")
        cr := ClientRect(hwnd)
        if !cr
            throw Error("cancelled")
        Banner.Hide()
        Sleep 80
        hbm := CaptureBitmap(cr.x, cr.y, cr.w, cr.h)
        fz := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale")
        fz.MarginX := 0, fz.MarginY := 0
        fz.Add("Picture", Format("x0 y0 w{} h{}", cr.w, cr.h), "HBITMAP:*" hbm)
        fz.Show(Format("x{} y{} w{} h{}", cr.x, cr.y, cr.w, cr.h))
        FreezeHwnd := fz.Hwnd
        if false {
        } else {
            Banner.Show(kind = "Reel"
                ? "Drag a box just inside the reel track. Drag again to redo it.`nEnter saves the box. Esc cancels."
                : "Drag a box over the area where shake buttons pop up.`nEnter saves the box. Esc cancels.", hwnd)
            sel := Outline(Pal.accent)
            box := DragBox(sel)
            if !box
                throw Error("cancelled")
            Cfg[kind "X1"] := Clamp((box.x - cr.x) / cr.w, 0, 1)
            Cfg[kind "Y1"] := Clamp((box.y - cr.y) / cr.h, 0, 1)
            Cfg[kind "X2"] := Clamp((box.x + box.w - cr.x) / cr.w, 0, 1)
            Cfg[kind "Y2"] := Clamp((box.y + box.h - cr.y) / cr.h, 0, 1)
            for k in ["X1", "Y1", "X2", "Y2"]
                Save(kind k)
            what := kind " area saved"
        }
        result := "saved"
    } catch as err {
        if (err.Message != "cancelled")
            result := "failed: " err.Message
    } finally {
        try Hotkey("*Esc", "Off")
        try Hotkey("*Enter", "Off")
        Banner.Hide()
        FreezeHwnd := 0
        if sel
            sel.Destroy()
        if fz
            fz.Destroy()
        if hbm
            DllCall("DeleteObject", "Ptr", hbm)
        MainGui.Show()
        Calibrating := false
        if Cfg["ShowAreas"]
            UpdateOverlay()
    }
    if (result = "saved") {
        SetPhase("idle", what, IdleHint())
        LogEvent(what)
    } else if (result = "cancel") {
        SetPhase("idle", "Ready", "Setup cancelled. Nothing changed.")
    } else {
        SetPhase("error", "Setup failed", SubStr(result, 9))
    }
}

CalEsc(*) {
    global CalFlag := "esc"
}

CalEnter(*) {
    global CalFlag := "enter"
}

WaitForCtrl() {
    KeyWait("Ctrl", "T3")
    t0 := A_TickCount
    while (CalFlag != "esc" && A_TickCount - t0 < 180000) {
        if GetKeyState("Ctrl", "P")
            return true
        Sleep 15
    }
    return false
}

DragBox(sel) {
    global CalFlag
    CalFlag := "", box := 0
    KeyWait("LButton", "T3")
    loop {
        if (CalFlag = "esc")
            return 0
        if (CalFlag = "enter") {
            if box
                return box
            CalFlag := ""
        }
        if GetKeyState("LButton", "P") {
            MouseGetPos(&sx, &sy)
            x := sx, y := sy, w := 0, h := 0
            while GetKeyState("LButton", "P") {
                MouseGetPos(&mx, &my)
                x := Min(sx, mx), y := Min(sy, my), w := Abs(mx - sx), h := Abs(my - sy)
                if (w >= 3 && h >= 2)
                    sel.Show(x, y, w, h)
                Sleep 10
            }
            if (w >= 8 && h >= 3)
                box := {x: x, y: y, w: w, h: h}
            sel.Raise()
            Banner.Raise()
        }
        Sleep 10
    }
}


PickPoint() {
    global CalFlag
    CalFlag := ""
    KeyWait("LButton", "T3")
    loop {
        if (CalFlag = "esc")
            return 0
        if GetKeyState("LButton", "P") {
            MouseGetPos(&mx, &my)
            KeyWait("LButton", "T3")
            return {x: mx, y: my}
        }
        Sleep 10
    }
}

CaptureBitmap(x, y, w, h) {
    sdc := DllCall("GetDC", "Ptr", 0, "Ptr")
    mdc := DllCall("CreateCompatibleDC", "Ptr", sdc, "Ptr")
    hbm := DllCall("CreateCompatibleBitmap", "Ptr", sdc, "Int", w, "Int", h, "Ptr")
    old := DllCall("SelectObject", "Ptr", mdc, "Ptr", hbm, "Ptr")
    DllCall("BitBlt", "Ptr", mdc, "Int", 0, "Int", 0, "Int", w, "Int", h, "Ptr", sdc, "Int", x, "Int", y, "UInt", 0x00CC0020)
    DllCall("SelectObject", "Ptr", mdc, "Ptr", old)
    DllCall("DeleteDC", "Ptr", mdc)
    DllCall("ReleaseDC", "Ptr", 0, "Ptr", sdc)
    return hbm
}

; Instruction strip near the top of the Roblox window. Never takes focus.
class Banner {
    static g := 0
    static Show(msg, hwnd, swatch := "") {
        this.Hide()
        g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000000")
        g.BackColor := Pal.bar
        g.MarginX := 0, g.MarginY := 0
        SetFontFor(g, "norm s" FZ(11) " c" Pal.text, "body")
        t := g.Add("Text", Format("x{} y{} Background{}", ZS(24), ZS(14), Pal.bar), msg)
        t.GetPos(, , &tw, &th)
        extra := 0
        if (swatch != "") {
            g.Add("Text", Format("x{} y{} w{} h{} Background{}", ZS(24) + tw + ZS(16), ZS(14) + (th - ZS(16)) // 2, ZS(16), ZS(16), swatch))
            extra := ZS(32)
        }
        g.Add("Text", Format("x0 y0 w{} h{} Background{}", Max(3, ZS(3)), th + ZS(28), Pal.accent))
        g.Show(Format("Hide w{} h{}", tw + extra + ZS(48), th + ZS(28)))
        WinRect(g.Hwnd, &bx, &by, &bw, &bh)
        cr := ClientRect(hwnd)
        x := cr ? cr.x + (cr.w - bw) // 2 : (A_ScreenWidth - bw) // 2
        y := cr ? cr.y + Round(cr.h * 0.05) : 40
        g.Show(Format("NA x{} y{}", x, y))
        RaiseNoActivate(g.Hwnd)
        StyleWindow(g.Hwnd)
        this.g := g
        Say(StrReplace(msg, "`n", " "))
    }
    static Raise() {
        if this.g
            RaiseNoActivate(this.g.Hwnd)
    }
    static Hide() {
        if this.g {
            try this.g.Destroy()
            this.g := 0
        }
    }
}

; Hollow rectangle drawn just outside a region. Never takes focus.
class Outline {
    __New(color, thick := 2) {
        this.t := thick, this.last := ""
        this.g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000000 -DPIScale")
        this.g.BackColor := color
    }
    Show(x, y, w, h) {
        t := this.t, ox := x - t, oy := y - t, ow := w + 2 * t, oh := h + 2 * t
        key := ox "," oy "," ow "," oh
        if (key = this.last)
            return
        this.last := key
        this.g.Show(Format("NA x{} y{} w{} h{}", ox, oy, ow, oh))
        WinSetRegion(Format("0-0 {1}-0 {1}-{2} 0-{2} 0-0 {3}-{3} {4}-{3} {4}-{5} {3}-{5} {3}-{3}"
            , ow, oh, t, ow - t, oh - t), "ahk_id " this.g.Hwnd)
        RaiseNoActivate(this.g.Hwnd)
    }
    Raise() {
        if (this.last != "")
            RaiseNoActivate(this.g.Hwnd)
    }
    Hide() {
        this.g.Hide()
        this.last := ""
    }
    Destroy() {
        try this.g.Destroy()
    }
}

UpdateOverlay() {
    global OutReel, OutShake, OutAq
    UsePhysicalPixels()
    if (!Cfg["ShowAreas"] || Calibrating)
        return HideOverlay()
    hwnd := FindRoblox()
    cr := hwnd ? ClientRect(hwnd) : 0
    if (!cr || WinGetMinMax("ahk_id " hwnd) = -1)
        return HideOverlay()
    if !OutReel
        OutReel := Outline(Pal.accent), OutShake := Outline(Pal.wait), OutAq := Outline(Pal.stop)
    a := AreaRect("Reel", cr), s := AreaRect("Shake", cr)
    OutShake.Show(s.x1, s.y1, s.w, s.h)
    OutReel.Show(a.x1, a.y1, a.w, a.h)
    nsp := UiSpot("aquariums", cr), nx := nsp.x, ny := nsp.y
    OutAq.Show(nx - 8, ny - 8, 16, 16)
}

HideOverlay() {
    if OutReel
        OutReel.Hide(), OutShake.Hide(), OutAq.Hide()
}

DestroyOverlays() {
    global OutReel, OutShake, OutAq
    if OutReel {
        OutReel.Destroy(), OutShake.Destroy(), OutAq.Destroy()
        OutReel := 0, OutShake := 0, OutAq := 0
    }
}

RaiseNoActivate(hwnd) {
    DllCall("SetWindowPos", "Ptr", hwnd, "Ptr", -1, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)
}

;==============================================================================
; Helpers
;==============================================================================
ZS(n) => Round(n * Zoom)
StepText(key) => (key = "Latency" && Cfg[key] = 0) ? "Auto" : Cfg[key]
FZ(n) => Max(6, Round(n * Zoom))
ToPhys(n) => Round(ZS(n) * A_ScreenDPI / 96)
Clamp(v, lo, hi) => Max(lo, Min(hi, v))
KeyName(k) => StrLen(k) = 1 ? StrUpper(k) : k
IdleHint() => "Press " KeyName(Cfg["ToggleKey"]) " to start or stop. " KeyName(Cfg["ExitKey"]) " quits."
IconOr(glyph, fallback) => HasIconFont ? glyph : fallback
PointOnScreen(x, y) => DllCall("MonitorFromPoint", "Int64", (y << 32) | (x & 0xFFFFFFFF), "UInt", 0, "Ptr") != 0

MonitorAt(x, y) {
    Loop MonitorGetCount() {
        MonitorGet(A_Index, &l, &t, &r, &b)
        if (x >= l && x < r && y >= t && y < b)
            return A_Index
    }
    return MonitorGetPrimary()
}

; Adds a Text control in design units (scaled by the zoom level).
AddT(page, x, y, w, h, text, role, size, color, bg, extra := "") {
    return AddRaw(page, ZS(x), ZS(y), w = "" ? "" : ZS(w), h = "" ? "" : ZS(h), text, role, size, color, bg, extra)
}

; Adds a Text control in window units (already scaled).
AddRaw(page, x, y, w, h, text, role, size, color, bg, extra := "") {
    SetFontFor(MainGui, "norm s" FZ(size) " c" color, role)
    opts := "x" x " y" y (w != "" ? " w" w : "") (h != "" ? " h" h : "") " Background" bg (extra != "" ? " " extra : "")
    ctl := MainGui.Add("Text", opts, text)
    if (page != 0 && page != "")
        Pages[page].ctls.Push(ctl)
    return ctl
}

; Sets a font with fallbacks: later faces win when they are installed.
SetFontFor(g, opts, role := "body") {
    static faces := Map(
        "body", ["Tahoma", "Segoe UI"],
        "display", ["Tahoma", "Segoe UI Semibold", "Bahnschrift SemiBold"],
        "num", ["Tahoma", "Segoe UI", "Bahnschrift"]
    )
    if (role = "icon") {
        g.SetFont(opts, "Tahoma")
        if (IconFace != "")
            g.SetFont(opts, IconFace)
        return
    }
    ; The black-and-white theme renders text with greyscale smoothing, so no
    ; ClearType colour fringes appear around it.
    if (IsObject(Pal) && Pal.HasOwnProp("mono") && !InStr(opts, " q"))
        opts .= " q4"
    for face in faces[role]
        g.SetFont(opts, face)
}

DetectIconFont() {
    global HasIconFont, IconFace
    for f in [["SegoeIcons.ttf", "Segoe Fluent Icons"], ["segmdl2.ttf", "Segoe MDL2 Assets"]]
        if FileExist(A_WinDir "\Fonts\" f[1])
            return (HasIconFont := true, IconFace := f[2])
}

WinRect(hwnd, &x, &y, &w, &h) {
    rc := Buffer(16, 0)
    DllCall("GetWindowRect", "Ptr", hwnd, "Ptr", rc)
    x := NumGet(rc, 0, "Int"), y := NumGet(rc, 4, "Int")
    w := NumGet(rc, 8, "Int") - x, h := NumGet(rc, 12, "Int") - y
}

; Dark title handling, rounded corners and a hairline border on Windows 11.
StyleWindow(hwnd) {
    buf := Buffer(4)
    c := Integer("0x" Pal.seam)
    border := ((c & 0xFF) << 16) | (c & 0xFF00) | ((c >> 16) & 0xFF)
    for attr, val in Map(20, Pal.dark ? 1 : 0, 33, 2, 34, border) {
        NumPut("UInt", val, buf)
        try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", attr, "Ptr", buf, "UInt", 4)
    }
}

Brush(color) {
    if !Brushes.Has(color) {
        c := Integer("0x" color)
        Brushes[color] := DllCall("CreateSolidBrush", "UInt", ((c & 0xFF) << 16) | (c & 0xFF00) | ((c >> 16) & 0xFF), "Ptr")
    }
    return Brushes[color]
}

FreeBrushes() {
    for k, b in Brushes
        DllCall("DeleteObject", "Ptr", b)
    Brushes.Clear()
}

FillBand(hdc, x1, y1, x2, y2, color) {
    rc := Buffer(16)
    NumPut("Int", x1, "Int", y1, "Int", x2, "Int", y2, rc)
    DllCall("FillRect", "Ptr", hdc, "Ptr", rc, "Ptr", Brush(color))
}

SetupTray() {
    try ApplyAppIcon()
    A_IconTip := APP_NAME
    A_TrayMenu.Delete()
    A_TrayMenu.Add("Show window", (*) => ShowFromTray())
    A_TrayMenu.Add("Start or stop fishing", (*) => ToggleMacro())
    A_TrayMenu.Add()
    A_TrayMenu.Add("Quit", (*) => ExitApp())
    A_TrayMenu.Default := "Show window"
}

ShowFromTray() {
    if IsObject(MainGui) {
        MainGui.Show()
        try WinActivate("ahk_id " MainGui.Hwnd)
    }
}

Cleanup(reason, code) {
    ReleaseMouse()
    if !NoSave {
        SaveGeometry()
        FlushSaves()
    }
    FreeBrushes()
    if LiveHbm
        DllCall("DeleteObject", "Ptr", LiveHbm)
    try DllCall("DeleteObject", "Ptr", UI.logoHbm)
    try Gdip.Stop()
    try DllCall("winmm\timeEndPeriod", "UInt", 1)
}


;==============================================================================
; Vision. Finds the reel bar and the fish marker for any rod or skin.
;
; Every rod look (rod plus skin) is learned once and kept as a rod profile:
; colour palettes for the track, the bar and the fish, the bar width, and the
; rows where the track's top and bottom edges sit. A new look is learned by
; holding the mouse for a moment and seeing which block of pixels moved with
; the bar, so no colour is assumed in advance. Pixels are classified through
; a lookup table built on demand, which keeps each frame under a millisecond.
;==============================================================================

; Captures a block of rows around the reel area in one BitBlt.
class BandGrab {
    __New(w, h) {
        this.w := w := Max(8, Integer(w)), this.h := h := Max(3, Integer(h)), this.stride := w * 4
        bi := Buffer(40, 0)
        NumPut("UInt", 40, bi, 0), NumPut("Int", w, bi, 4), NumPut("Int", -h, bi, 8)
        NumPut("UShort", 1, bi, 12), NumPut("UShort", 32, bi, 14)
        this.dc := DllCall("CreateCompatibleDC", "Ptr", 0, "Ptr")
        this.bmp := DllCall("CreateDIBSection", "Ptr", this.dc, "Ptr", bi, "UInt", 0, "Ptr*", &bits := 0, "Ptr", 0, "UInt", 0, "Ptr")
        this.bits := bits
        this.old := DllCall("SelectObject", "Ptr", this.dc, "Ptr", this.bmp, "Ptr")
        this.cols := Buffer(w * 4, 0)      ; colour of each column (median of three rows)
        this.lab := Buffer(w + 1, 0)       ; class of each column
    }
    Grab(x, y) {
        sdc := DllCall("GetDC", "Ptr", 0, "Ptr")
        DllCall("BitBlt", "Ptr", this.dc, "Int", 0, "Int", 0, "Int", this.w, "Int", this.h
            , "Ptr", sdc, "Int", x, "Int", y, "UInt", 0x00CC0020)
        DllCall("ReleaseDC", "Ptr", 0, "Ptr", sdc)
    }
    __Delete() {
        DllCall("SelectObject", "Ptr", this.dc, "Ptr", this.old)
        DllCall("DeleteObject", "Ptr", this.bmp)
        DllCall("DeleteDC", "Ptr", this.dc)
    }
}

; Geometry of the captured band: the reel area plus a margin above and below,
; where the track's edges are. r1..r3 are sample rows inside the track.
VisionGeo(a) {
    m := Max(4, Round(a.h * 0.9))
    geo := {x: a.x1, y: a.y1 - m, w: a.w, h: a.h + 2 * m + 1, m: m, ih: Max(1, a.h)}
    geo.r1 := m + Round(a.h * 0.25), geo.r2 := m + Round(a.h * 0.5), geo.r3 := m + Round(a.h * 0.75)
    return geo
}

VisionGrab(b, geo) {
    b.Grab(geo.x, geo.y)
    b.geo := geo
    ColumnColors(b, geo)
}

; Colour of each column: the per-channel median of three rows inside the
; track, which ignores a thin highlight or outline crossing one of them.
ColumnColors(b, geo) {
    p := b.bits, s := b.stride, o1 := geo.r1 * s, o2 := geo.r2 * s, o3 := geo.r3 * s
    cols := b.cols, w := b.w, x := 0
    while (x < w) {
        o := x * 4
        a := NumGet(p, o1 + o, "UInt"), q := NumGet(p, o2 + o, "UInt"), c := NumGet(p, o3 + o, "UInt")
        ar := (a >> 16) & 255, qr := (q >> 16) & 255, cr := (c >> 16) & 255
        mr := ar > qr ? (qr > cr ? qr : (ar > cr ? cr : ar)) : (ar > cr ? ar : (qr > cr ? cr : qr))
        ag := (a >> 8) & 255, qg := (q >> 8) & 255, cg := (c >> 8) & 255
        mg := ag > qg ? (qg > cg ? qg : (ag > cg ? cg : ag)) : (ag > cg ? ag : (qg > cg ? cg : qg))
        ab := a & 255, qb := q & 255, cb := c & 255
        mb := ab > qb ? (qb > cb ? qb : (ab > cb ? cb : ab)) : (ab > cb ? ab : (qb > cb ? cb : qb))
        NumPut("UInt", (mr << 16) | (mg << 8) | mb, cols, o)
        x++
    }
}

; Largest per-channel difference between two 0xRRGGBB colours.
ColDist(a, b) {
    return Max(Abs(((a >> 16) & 255) - ((b >> 16) & 255)), Abs(((a >> 8) & 255) - ((b >> 8) & 255)), Abs((a & 255) - (b & 255)))
}

;------------------------------------------------------------------------------
; Rod profiles
;------------------------------------------------------------------------------
NewProfile(name, track, bar, fish, barW := 0) {
    global ProfSeq
    ProfSeq++
    p := FillProfile({id: "p" ProfSeq, name: name, track: track, bar: bar, fish: fish, barW: barW})
    ResetLut(p)
    return p
}

; Gives a look every field the rest of the macro expects. Looks read back
; from the settings file, and the stand-ins built to test library colours,
; are made this way too, so a look saved by an older version can't arrive
; missing something.
FillProfile(p) {
    for k, v in Map("id", "", "name", "Rod", "track", [], "bar", [], "fish", [], "barW", 0
        , "tolT", 24, "tolB", 24, "tolF", 22, "edgeT", "", "edgeB", "", "sovereign", 0
        , "reels", 0, "lib", "", "used", 0, "relearn", false, "greenBar", false, "probe", false, "kind", "")
        if !p.HasOwnProp(k)
            p.%k% := v
    return p
}

ResetLut(p) {
    p.lut := Buffer(32768, 255)
}

; Class of one 15-bit colour key: 1 track, 2 bar, 3 fish, 0 anything else.
; The nearest palette colour wins, within that palette's tolerance.
ClassifyKey(p, k) {
    r := ((k >> 10) & 31) * 8 + 4, g := ((k >> 5) & 31) * 8 + 4, b := (k & 31) * 8 + 4
    ; a green-zone rod (Verdant Oath): green inside the bar is still bar
    if (p.greenBar && IsGreen(r, g, b)) {
        NumPut("UChar", 2, p.lut, k)
        return 2
    }
    best := 0, bd := 999
    for cls, list in [p.track, p.bar, p.fish] {
        tol := cls = 1 ? p.tolT : cls = 2 ? p.tolB : p.tolF
        for c in list {
            d := Max(Abs(((c >> 16) & 255) - r), Abs(((c >> 8) & 255) - g), Abs((c & 255) - b))
            if (d <= tol && d < bd)
                bd := d, best := cls
        }
    }
    NumPut("UChar", best, p.lut, k)
    return best
}

; Labels every column, then finds the bar (the biggest block of bar colour,
; allowing small gaps where the fish or an outline covers it) and the fish
; (fish colour anywhere, a gap inside the bar, or an odd colour outside it).
; predFish, when known, breaks ties toward where the fish was.
VisionScan(b, p, predFish := -1) {
    if (p.kind = "box")
        return BoxScan(b, b.geo, predFish, p)
    w := b.w, cols := b.cols, lab := b.lab, lut := p.lut, covered := 0, x := 0
    while (x < w) {
        c := NumGet(cols, x * 4, "UInt")
        k := ((c >> 9) & 0x7C00) | ((c >> 6) & 0x3E0) | ((c >> 3) & 0x1F)
        l := NumGet(lut, k, "UChar")
        if (l = 255)
            l := ClassifyKey(p, k)
        NumPut("UChar", l, lab, x)
        covered += (l != 0)
        x++
    }
    gapMax := Max(4, Round(w * 0.045))
    bestN := 0, bl := -1, br := -1, cs := -1, cl := -1, cn := 0, x := 0
    while (x < w) {
        if (NumGet(lab, x, "UChar") = 2) {
            if (cs >= 0 && x - cl - 1 > gapMax) {
                if (cn > bestN)
                    bestN := cn, bl := cs, br := cl
                cs := -1
            }
            if (cs < 0)
                cs := x, cn := 0
            cl := x, cn++
        }
        x++
    }
    if (cs >= 0 && cn > bestN)
        bestN := cn, bl := cs, br := cl
    bar := bestN >= Max(3, w * 0.02)
    ; fish candidates
    ; Unknown colours off the bar may be the fish, except while probing a
    ; built-in style: it knows no track colours yet, so unknown means track.
    uf := !p.probe
    maxF := Max(3, Round(w * 0.12)), fx := -1, fBest := -1e9, rs := -1, fishN := 0, fishCol := false, x := 0
    while (x <= w) {
        isF := false
        if (x < w) {
            l := NumGet(lab, x, "UChar")
            inBar := bar && x > bl && x < br
            isF := (l = 3) || (inBar && l != 2) || (uf && !inBar && l = 0 && !(bar && x >= bl - 2 && x <= br + 2))
        }
        if isF {
            if (rs < 0)
                rs := x, fishN := 0
            fishN += (NumGet(lab, x, "UChar") = 3)
        } else if (rs >= 0) {
            len := x - rs
            if (len <= maxF) {
                cen := rs + (len - 1) / 2
                inside := bar && cen > bl && cen < br
                sc := 4 * fishN + (inside ? 2 : 1) * len
                if (predFish >= 0)
                    sc -= Abs(cen - predFish) / Max(1, w * 0.08)
                if (sc > fBest)
                    fBest := sc, fx := cen, fishCol := fishN > 0
            }
            rs := -1
        }
        x++
    }
    return {bar: bar, bl: bl, br: br, fish: fx >= 0, fx: fx, cover: covered / w, n: bestN, fishCol: fishCol}
}

; Fraction of sampled columns with a sharp brightness change across a row.
EdgeStrength(b, row) {
    if (row < 1 || row >= b.h - 1)
        return 0
    p := b.bits, s := b.stride, up := (row - 1) * s, dn := (row + 1) * s
    n := 0, hit := 0, x := 2, w := b.w - 2
    while (x < w) {
        c := NumGet(p, up + x * 4, "UInt"), d := NumGet(p, dn + x * 4, "UInt")
        l1 := ((c >> 16) & 255) * 2 + ((c >> 8) & 255) * 5 + (c & 255)
        l2 := ((d >> 16) & 255) * 2 + ((d >> 8) & 255) * 5 + (d & 255)
        hit += (Abs(l1 - l2) >= 150)
        n++, x += 5
    }
    return n ? hit / n : 0
}

; Strongest horizontal edge above and below the track, if both are clear.
FindEdges(b, geo) {
    bt := 0, st := 0, bb := 0, sb := 0
    r := 1
    while (r <= geo.m + 2) {
        s := EdgeStrength(b, r)
        if (s > st)
            st := s, bt := r
        r++
    }
    r := geo.m + geo.ih - 2
    while (r <= b.h - 2) {
        s := EdgeStrength(b, r)
        if (s > sb)
            sb := s, bb := r
        r++
    }
    return {top: bt, bot: bb, st: st, sb: sb, ok: st >= 0.45 && sb >= 0.45}
}

; Is the learned track outline still there? Checks the stored rows +-1.
EdgesPresent(b, geo, p) {
    if (p.edgeT = "")
        return -1
    t := geo.m + Round(p.edgeT * geo.ih), d := geo.m + geo.ih + Round(p.edgeB * geo.ih)
    st := Max(EdgeStrength(b, t - 1), EdgeStrength(b, t), EdgeStrength(b, t + 1))
    sb := Max(EdgeStrength(b, d - 1), EdgeStrength(b, d), EdgeStrength(b, d + 1))
    return (st >= 0.3 && sb >= 0.3) ? 1 : 0
}

RememberEdges(p, e, geo) {
    p.edgeT := Round((e.top - geo.m) / geo.ih, 3), p.edgeB := Round((e.bot - geo.m - geo.ih) / geo.ih, 3)
    SaveRodProfile(p)
}

;------------------------------------------------------------------------------
; Learning a new look
;------------------------------------------------------------------------------
; Greedy colour clustering. Returns the mean of every cluster holding at
; least minShare of the samples, largest first (at most `most`).
VClusters(colors, radius, minShare, most := 6) {
    cl := []
    for c in colors {
        r := (c >> 16) & 255, g := (c >> 8) & 255, b := c & 255, hit := 0
        for k in cl {
            if (Abs(k.r - r) <= radius && Abs(k.g - g) <= radius && Abs(k.b - b) <= radius) {
                hit := k
                break
            }
        }
        if !hit {
            if (cl.Length >= 16)
                continue
            hit := {r: r, g: g, b: b, sr: 0, sg: 0, sb: 0, n: 0}
            cl.Push(hit)
        }
        hit.sr += r, hit.sg += g, hit.sb += b, hit.n++
        hit.r := hit.sr // hit.n, hit.g := hit.sg // hit.n, hit.b := hit.sb // hit.n
    }
    total := Max(1, colors.Length), keep := []
    for k in cl
        if (k.n >= total * minShare)
            keep.Push(k)
    ; largest first
    Loop keep.Length - 1 {
        i := A_Index
        Loop keep.Length - i {
            j := A_Index
            if (keep[j].n < keep[j + 1].n)
                t := keep[j], keep[j] := keep[j + 1], keep[j + 1] := t
        }
    }
    out := []
    for k in keep {
        if (out.Length >= most)
            break
        out.Push((k.r << 16) | (k.g << 8) | k.b)
    }
    return out
}

; Finds the bar from two frames between which it moved: the shift that
; explains the most changed columns is the bar's movement, and the columns
; it explains are the bar's leading and trailing strips (or all of a
; patterned bar). Returns {bl, br, dx} for frame 1, or 0.
FindMovedBar(c0, c1, w) {
    ch := [], x := 0
    while (x < w) {
        if (ColDist(NumGet(c1, x * 4, "UInt"), NumGet(c0, x * 4, "UInt")) > 30)
            ch.Push(x)
        x++
    }
    if (ch.Length < 6)
        return 0
    ; The shift is scored over every column in the changed span, changed or
    ; not. Shifted too far, the bar maps its own columns onto old track;
    ; too little, its leading strip goes unexplained. So the true shift is
    ; the one lowest cost, on flat bars and gradients alike. Distances are
    ; capped so the fish, which moves on its own, can't dominate.
    a := ch[1], z := ch[ch.Length], span := z - a + 1
    maxDx := Min(120, w // 3), bestDx := 0, bestCost := 1e9, dx := -maxDx
    while (dx <= maxDx) {
        if (Abs(dx) >= 3) {
            sum := 0, n := 0, x := a
            while (x <= z) {
                xs := x - dx
                if (xs >= 0 && xs < w) {
                    u := NumGet(c1, x * 4, "UInt"), v := NumGet(c0, xs * 4, "UInt")
                    e := Max(Abs(((u >> 16) & 255) - ((v >> 16) & 255)), Abs(((u >> 8) & 255) - ((v >> 8) & 255)), Abs((u & 255) - (v & 255)))
                    sum += e < 60 ? e : 60, n++
                }
                x++
            }
            if (n >= span * 0.6) {
                c := sum / n
                if (c < bestCost - 1e-9 || (Abs(c - bestCost) <= 1e-9 && Abs(dx) < Abs(bestDx)))
                    bestCost := c, bestDx := dx
            }
        }
        dx++
    }
    if !bestDx
        return 0
    if (bestCost > 20)
        return 0
    ; The track just outside the changed span, on each side.
    tl := MedianColor(c1, a - 16, a - 4, w), tr := MedianColor(c1, z + 4, z + 16, w)
    if (tl < 0)
        tl := tr
    if (tr < 0)
        tr := tl
    if (tl < 0)
        return 0
    ; A bar column now is not track-coloured and holds what sat one shift
    ; back. That excludes the strip the bar vacated (track now) and usually
    ; the fish (it moves on its own); the longest such run, bridging gaps
    ; up to a fish's width, is the bar.
    fishMax := Max(4, Round(w * 0.025)), bl := -1, br := -1, rs := -1, rl := -99
    x := Max(0, a - 20), xe := Min(w - 1, z + 20)
    while (x <= xe) {
        c := NumGet(c1, x * 4, "UInt")
        isBar := ColDist(c, tl) > 24 && ColDist(c, tr) > 24
        if isBar {
            xs := x - bestDx
            if (xs >= 0 && xs < w)
                isBar := ColDist(c, NumGet(c0, xs * 4, "UInt")) <= 20
        }
        if isBar {
            if (rs >= 0 && x - rl - 1 > fishMax) {
                if (rl - rs > br - bl)
                    bl := rs, br := rl
                rs := -1
            }
            if (rs < 0)
                rs := x
            rl := x
        }
        x++
    }
    if (rs >= 0 && rl - rs > br - bl)
        bl := rs, br := rl
    if (bl < 0)
        return 0
    bw := br - bl + 1
    if (bw < w * 0.03 || bw > w * 0.85)
        return 0
    return {bl: bl, br: br, dx: bestDx, lo: a, hi: z, n: bw, ch: ch.Length, tl: tl, tr: tr, cost: Round(bestCost, 1)}
}

; The median of the packed colours in columns x0..x1 (clipped), or -1.
MedianColor(cols, x0, x1, w) {
    v := []
    x := Max(0, x0)
    while (x <= Min(w - 1, x1))
        v.Push(NumGet(cols, x * 4, "UInt") & 0xFFFFFF), x++
    if !v.Length
        return -1
    s := ""
    for c in v
        s .= c "`n"
    s := Sort(RTrim(s, "`n"), "N")
    return Integer(StrSplit(s, "`n")[(v.Length + 1) // 2])
}

; True when the colours just outside the found bar are the track's, on
; each side that isn't the end of the track. The check looks past a fish's
; width, so a fish resting against the edge doesn't fail it; a bar learned
; from only part of a gradient does, since past its edge the bar goes on.
BordersTrack(cols, w, bl, br, tl, tr) {
    reach := 5 + Max(4, Round(w * 0.025))
    for side in [-1, 1] {
        e := side < 0 ? bl : br, ref := side < 0 ? tl : tr
        if (side < 0 ? e <= 5 : e >= w - 6)
            continue
        n := 0, good := 0, k := 2
        while (k <= reach) {
            x := e + side * k
            if (x < 0 || x >= w)
                break
            n++, good += ColDist(NumGet(cols, x * 4, "UInt"), ref) <= 30
            k++
        }
        if (n >= 4 ? good < 4 : good < n)
            return false
    }
    return true
}

; Builds a profile from a frame where the bar is known to span [bl, br]:
; bar colours from inside, track colours from outside, and fish colours
; from narrow runs that fit neither.
ProfileFromFrame(cols, w, bl, br, name := "") {
    inside := [], outside := []
    Loop w {
        x := A_Index - 1, c := NumGet(cols, x * 4, "UInt")
        if (x >= bl && x <= br)
            inside.Push(c)
        else if (x < bl - 2 || x > br + 2)
            outside.Push(c)
    }
    barPal := VClusters(inside, 18, 0.08, 6)
    trackPal := VClusters(outside, 18, 0.10, 5)
    if (!barPal.Length || !trackPal.Length)
        return 0
    ; Odd columns fit neither palette: the fish, if it is narrow. Inside the
    ; bar, anything that isn't bar colour counts, even if it matches the
    ; track: a dark fish on a dark track still stands out against the bar
    ; it sits on, and without its colour it would vanish once it left the bar.
    odd := [], runs := [], x := 0, rs := -1
    while (x <= w) {
        isOdd := false
        if (x < w) {
            c := NumGet(cols, x * 4, "UInt"), isOdd := true
            if (x < bl || x > br)
                for t in trackPal
                    if (ColDist(c, t) <= 26) {
                        isOdd := false
                        break
                    }
            if isOdd
                for t in barPal
                    if (ColDist(c, t) <= 26) {
                        isOdd := false
                        break
                    }
        }
        if isOdd {
            if (rs < 0)
                rs := x
        } else if (rs >= 0) {
            if (x - rs <= w * 0.12 && !(x - rs <= 2 && (Abs(rs - bl) <= 2 || Abs(x - 1 - br) <= 2))) {
                rc := []
                Loop x - rs
                    c := NumGet(cols, (rs + A_Index - 1) * 4, "UInt"), odd.Push(c), rc.Push(c)
                runs.Push({x0: rs, x1: x - 1, cols: rc})
            }
            rs := -1
        }
        x++
    }
    ; Artwork printed on the bar (the arrows near each end of Fisch's bar)
    ; shows up in two or more separate places inside it, in the same colour;
    ; the fish is a single marker. Such colours join the bar's palette and
    ; are dropped from the fish's, so the arrows read as bar: the bar stays
    ; one piece and the fish can't be mistaken for an arrow.
    decor := [], inside := []
    for r in runs
        if (r.x0 >= bl && r.x1 <= br)
            inside.Push(VClusters(r.cols, 16, 0.15, 3))
    for i, ci in inside
        for c in ci
            for j, cj in inside
                if (j != i)
                    for c2 in cj
                        if (ColDist(c, c2) <= 30) {
                            decor.Push(c)
                            break 2
                        }
    if decor.Length {
        for c in decor {
            have := false
            for bc in barPal
                have := have || ColDist(c, bc) <= 18
            if !have
                barPal.Push(c)
        }
        keep := []
        for c in odd {
            art := false
            for dc in decor
                art := art || ColDist(c, dc) <= 30
            if !art
                keep.Push(c)
        }
        odd := keep
    }
    fishPal := odd.Length ? VClusters(odd, 16, 0.2, 3) : []
    ; Fish colours close to the track are kept only when the fish has none of
    ; its own: they rescue a dark fish on a dark track, but for an outlined
    ; fish they would make plain track read as fish.
    own := [], near := []
    for f in fishPal {
        isNear := false
        for t in trackPal
            if (ColDist(f, t) <= 26) {
                isNear := true
                break
            }
        (isNear ? near : own).Push(f)
    }
    if own.Length
        fishPal := own
    p := NewProfile(name != "" ? name : NextRodName(barPal, fishPal), trackPal, barPal, fishPal, (br - bl + 1) / w)
    p.lib := LibMatch(barPal, fishPal)
    if (p.lib != "" && name = "")
        p.name := RodById(p.lib).name
    return p
}

; Learns a new look while the reel is up: holds the mouse until the bar has
; visibly moved (or releases if it is pinned right), then learns from the
; two frames. Returns {prof, d} or 0. The mouse is left released.
LearnLook(b, geo, &trace := "") {
    VisionGrab(b, geo)
    c0 := Buffer(b.w * 4)
    DllCall("RtlMoveMemory", "Ptr", c0, "Ptr", b.cols, "UPtr", b.w * 4)
    held := true
    Click("Down")
    t0 := A_TickCount, mv := 0, prev := 0, ok := false
    loop {
        FineSleep(12)
        VisionGrab(b, geo)
        mv := FindMovedBar(c0, b.cols, b.w)
        ; A find counts once the next frame agrees: same width, and moved on
        ; by exactly the extra shift. One-off mistakes rarely repeat.
        if (mv && Abs(mv.dx) >= 10) {
            if (prev && Abs((mv.br - mv.bl) - (prev.br - prev.bl)) <= 3 && Abs((mv.bl - prev.bl) - (mv.dx - prev.dx)) <= 3) {
                ok := true
                break
            }
            prev := mv
        } else {
            prev := 0
        }
        if (A_TickCount - t0 > 420) {
            if !held
                break
            ; nothing confirmed while holding: the bar may be pinned right, so release
            Click("Up")
            held := false
            DllCall("RtlMoveMemory", "Ptr", c0, "Ptr", b.cols, "UPtr", b.w * 4)
            t0 := A_TickCount, prev := 0
        }
    }
    if held
        Click("Up")
    if !ok {
        trace := mv ? "the bar's position didn't hold steady between frames" : "no block moved with the bar"
        return 0
    }
    if !BordersTrack(b.cols, b.w, mv.bl, mv.br, mv.tl, mv.tr) {
        trace := Format("check failed (bar {}-{} doesn't meet the track at both edges, shift {})", mv.bl, mv.br, mv.dx)
        return 0
    }
    p := ProfileFromFrame(b.cols, b.w, mv.bl, mv.br)
    if !p {
        trace := "colours could not be separated"
        return 0
    }
    d := VisionScan(b, p)
    if (!d.bar || Abs(d.bl - mv.bl) > 6 || Abs(d.br - mv.br) > 6 || d.cover < 0.8) {
        trace := Format("check failed (bar {} {}-{} vs {}-{}, cover {:.2f}, shift {}, span {}-{})"
            , d.bar, d.bl, d.br, mv.bl, mv.br, d.cover, mv.dx, mv.lo, mv.hi)
        return 0
    }
    trace := Format("learned: bar {}-{}, moved {} px (span {}-{}, cost {})", mv.bl, mv.br, mv.dx, mv.lo, mv.hi, mv.cost)
    return {prof: p, d: d}
}

; Tries the known looks, most recent first. A look matches when most of the
; row fits its palettes and the bar is found at a plausible width.
MatchProfile(b, geo) {
    for p in RodProfiles {
        FillProfile(p)          ; a look from another version may lack a field
        d := VisionScan(b, p)
        if (!d.bar || d.cover < 0.8)
            continue
        if (p.barW > 0 && Abs((d.br - d.bl + 1) / b.w - p.barW) > Max(0.04, p.barW * 0.3))
            continue
        if (EdgesPresent(b, geo, p) = 0)
            continue
        return {prof: p, d: d}
    }
    return 0
}

; Library looks (rods with their own reel colours) seed a full profile the
; first time they are seen.
; One built-in reel style against the reel: its own bar and fish colours
; must show, then the track's colours are taken from this frame so the reel
; can be told from scenery. Nothing here is saved.
ProbeLib(b, lib) {
    w := b.w, bars := [], fishes := []
    for h in lib.bar
        bars.Push(Integer("0x" h))
    for h in lib.fish
        fishes.Push(Integer("0x" h))
    green := lib.HasOwnProp("greenBar") && lib.greenBar
    if (lib.HasOwnProp("kind") && lib.kind = "box") {
        ; read by shape (see BoxScan): no colours to match
        d := BoxScan(b, b.geo)
        if !(d.bar && d.fish)
            return 0
        p := FillProfile({name: CurRodName != "" ? CurRodName : lib.name, lib: lib.id, kind: "box"
            , barW: (d.br - d.bl + 1) / b.w, id: "rod:" (CurRodName != "" ? CurRodName : lib.id)})
        ResetLut(p)
        return {prof: p, d: d}
    }
    probe := FillProfile({name: lib.name, bar: bars, fish: fishes, tolB: lib.bt + 6, tolF: lib.ft + 6, greenBar: green, probe: true})
    ResetLut(probe)
    d := VisionScan(b, probe)
    ; the rod's own fish colour, and mostly its own bar colours
    if !(d.bar && d.fish && d.fishCol && d.n >= 0.6 * (d.br - d.bl + 1))
        return 0
    bw := (d.br - d.bl + 1) / w
    if (bw < 0.03 || bw > 0.85)
        return 0
    p := ProfileFromFrame(b.cols, w, d.bl, d.br, lib.name)
    if !p
        return 0
    ; the style's own colours plus the exact shades on screen (kept in memory only)
    for h in bars
        p.bar.InsertAt(1, h)
    for f in fishes
        p.fish.Push(f)
    p.lib := lib.id, p.greenBar := green
    p.id := "rod:" (CurRodName != "" ? CurRodName : lib.id)
    p.name := CurRodName != "" ? CurRodName : lib.name
    ResetLut(p)
    d2 := VisionScan(b, p)
    return (d2.bar && d2.cover >= 0.75) ? {prof: p, d: d2} : 0
}

MatchLibrary(b) {
    for lib in RodLib
        if (r := ProbeLib(b, lib))
            return r
    return 0
}

; The reel style for this reel. The rod name read from the hotbar picks it;
; if that isn't known, every built-in style is tried and the best fit wins.
; The chosen style is kept for this session only (never saved), so the next
; reel is recognized at once.
MatchPrecoded(b, geo) {
    ids := []
    if (CurRodLib != "")
        ids.Push(CurRodLib)
    else
        for lib in RodLib
            ids.Push(lib.id)
    best := 0, bestScore := 0, bestId := ""
    for id in ids {
        if SessionLooks.Has(id) {
            p := FillProfile(SessionLooks[id])
            d := VisionScan(b, p)
            if (d.bar && d.cover >= 0.75 && EdgesPresent(b, geo, p) != 0) {
                sc := d.cover + (d.fish ? 0.2 : 0)
                if (sc > bestScore)
                    best := {prof: p, d: d}, bestScore := sc, bestId := id
                continue
            }
        }
        lib := 0
        for l in RodLib
            if (l.id = id)
                lib := l
        if (lib && (r := ProbeLib(b, lib))) {
            sc := r.d.cover + (r.d.fish ? 0.2 : 0)
            if (sc > bestScore)
                best := r, bestScore := sc, bestId := id
        }
    }
    if best
        SessionLooks[bestId] := best.prof
    return best
}

IsGreen(r, g, b) => g >= r + 30 && g >= b + 15 && g >= 70

; The centre column of the green zone inside the found bar, or -1.
GreenZone(b, d) {
    best := 0, bs := -1, rs := -1, x := d.bl
    while (x <= d.br + 1) {
        on := false
        if (x <= d.br) {
            c := NumGet(b.cols, x * 4, "UInt")
            on := IsGreen((c >> 16) & 255, (c >> 8) & 255, c & 255)
        }
        if on {
            if (rs < 0)
                rs := x
        } else if (rs >= 0) {
            if (x - rs > best)
                best := x - rs, bs := rs
            rs := -1
        }
        x++
    }
    return best >= 3 ? bs + (best - 1) / 2 : -1
}

LibMatch(barPal, fishPal) {
    for lib in RodLib {
        ok := false
        for h in lib.bar {
            for c in barPal
                if (ColDist(Integer("0x" h), c) <= 16)
                    ok := true
        }
        if (!ok || !fishPal.Length)     ; a library name needs its fish colour too
            continue
        for h in lib.fish
            for c in fishPal
                if (ColDist(Integer("0x" h), c) <= 18)
                    return lib.id
    }
    return ""
}

NextRodName(barPal, fishPal) {
    n := 1
    for p in RodProfiles
        if RegExMatch(p.name, "^Rod look (\d+)$", &m)
            n := Max(n, m[1] + 1)
    return "Rod look " n
}

; Adds a newly learned look, or refreshes a look it duplicates.
AdoptProfile(p) {
    FillProfile(p)
    for q in RodProfiles {
        if (q.id = p.id)
            return q
        same := true
        for c in p.bar {
            hit := false
            for d in q.bar
                if (ColDist(c, d) <= 14)
                    hit := true
            if !hit {
                same := false
                break
            }
        }
        if (same && Abs(q.barW - p.barW) <= 0.03 && p.bar.Length) {
            q.track := p.track, q.fish := p.fish.Length ? p.fish : q.fish, q.barW := p.barW
            ResetLut(q)
            SaveRodProfile(q)
            return q
        }
    }
    RodProfiles.InsertAt(1, p)
    SaveRodProfile(p)
    return p
}

TouchProfile(p) {
    for i, q in RodProfiles
        if (q = p) {
            if (i > 1)
                RodProfiles.RemoveAt(i), RodProfiles.InsertAt(1, p)
            break
        }
}

ProfById(id) {
    for p in RodProfiles
        if (p.id = id)
            return p
    return 0
}

;------------------------------------------------------------------------------
; Storage: [Looks] in FischMacro.ini, one line per look.
;   p3=Halibut Harpoon|0.380|1B2733,1C2834|5D52A8|0D0B0B|-0.150|0.080|0|12|halibut
;------------------------------------------------------------------------------
LoadRodProfiles() {
    global ProfSeq
    try section := IniRead(IniPath, "Looks")
    catch
        return
    Loop Parse, section, "`n", "`r" {
        if !RegExMatch(A_LoopField, "^(p\d+)=(.*)$", &m)
            continue
        f := StrSplit(m[2], "|")
        if (f.Length < 10)
            continue
        p := FillProfile({id: m[1], name: f[1], barW: f[2] + 0, track: HexList(f[3]), bar: HexList(f[4]), fish: HexList(f[5])
            , edgeT: f[6] = "" ? "" : f[6] + 0, edgeB: f[7] = "" ? "" : f[7] + 0, sovereign: f[8] + 0
            , reels: f[9] + 0, lib: f[10]})
        ; Looks saved before bar artwork was handled may have learned an
        ; arrow as the fish: learn their colours again on the next reel.
        p.relearn := f.Length < 11 || (f[11] + 0) < LOOK_FORMAT
        if (!p.track.Length || !p.bar.Length)
            continue
        ResetLut(p)
        RodProfiles.Push(p)
        ProfSeq := Max(ProfSeq, SubStr(p.id, 2) + 0)
    }
}

SaveRodProfile(p) => 0            ; reel styles are built in; nothing about rods is saved

ForgetProfile(p) {
    for i, q in RodProfiles
        if (q = p) {
            RodProfiles.RemoveAt(i)
            break
        }
    if !NoSave
        try IniDelete(IniPath, "Looks", p.id)
}

HexList(s) {
    out := []
    for h in StrSplit(s, ",")
        if RegExMatch(h, "i)^[0-9a-f]{6}$")
            out.Push(Integer("0x" h))
    return out
}

HexJoin(list) {
    s := ""
    for c in list
        s .= (s = "" ? "" : ",") Format("{:06X}", c)
    return s
}

;------------------------------------------------------------------------------
; Teaching a look by hand from a frozen frame: the user clicks the bar and
; the fish. The bar's extent is grown from the click along the track row.
;------------------------------------------------------------------------------
TeachLook(b, geo, barX, fishX) {
    cols := b.cols, w := b.w
    barX := Clamp(barX, 0, w - 1), fishX := Clamp(fishX, 0, w - 1)
    ref := NumGet(cols, barX * 4, "UInt"), bl := barX, br := barX
    ; grow while colours stay close to the bar's running range
    while (bl > 0 && ColDist(NumGet(cols, (bl - 1) * 4, "UInt"), ref) <= 40)
        bl--
    while (br < w - 1 && ColDist(NumGet(cols, (br + 1) * 4, "UInt"), ref) <= 40)
        br++
    if (fishX >= bl && fishX <= br) {
        ; the fish sits inside the bar: bridge across it
        l := bl, r := br
        while (r < w - 1 && ColDist(NumGet(cols, (r + 1) * 4, "UInt"), ref) > 40 && r - fishX < w * 0.06)
            r++
        while (r < w - 1 && ColDist(NumGet(cols, (r + 1) * 4, "UInt"), ref) <= 40)
            r++
        br := Max(br, r)
    }
    if ((br - bl + 1) < w * 0.03)
        return 0
    p := ProfileFromFrame(cols, w, bl, br)
    if !p
        return 0
    fc := []
    Loop 5 {
        x := Clamp(fishX + A_Index - 3, 0, w - 1)
        fc.Push(NumGet(cols, x * 4, "UInt"))
    }
    for c in VClusters(fc, 14, 0.2, 2)
        p.fish.Push(c)
    ResetLut(p)
    p.name := "Taught " p.name
    return p
}

; A picture of what the macro sees, for the Live tab and snapshots: the band
; itself, then a strip showing each column's class (dark: other, grey: track,
; white: bar, light grey: fish), with the bar outlined and the fish marked by
; a dashed line. mono draws the band in greys for the black-and-white theme.
; Everything is drawn with native fills, so it costs about a millisecond.
; Returns an HBITMAP the caller must delete.
VisionPicture(b, d, dw, dh, mono := false) {
    static br := 0
    if !br {
        br := Map()
        for name, c in Map("other", 0x303030, "track", 0x6E6E6E, "bar", 0xFFFFFF, "fish", 0xB4B4B4, "white", 0xFFFFFF, "black", 0x000000, "none", 0x161616)
            br[name] := DllCall("CreateSolidBrush", "UInt", c, "Ptr")
    }
    dw := Max(16, dw), dh := Max(24, dh)
    stripH := 12, bandH := dh - stripH - 2
    bi := Buffer(40, 0)
    NumPut("UInt", 40, bi, 0), NumPut("Int", dw, bi, 4), NumPut("Int", -dh, bi, 8)
    NumPut("UShort", 1, bi, 12), NumPut("UShort", 32, bi, 14)
    sdc := DllCall("GetDC", "Ptr", 0, "Ptr")
    mdc := DllCall("CreateCompatibleDC", "Ptr", sdc, "Ptr")
    hbm := DllCall("CreateDIBSection", "Ptr", mdc, "Ptr", bi, "UInt", 0, "Ptr*", &bits := 0, "Ptr", 0, "UInt", 0, "Ptr")
    old := DllCall("SelectObject", "Ptr", mdc, "Ptr", hbm, "Ptr")
    rc := Buffer(16)
    R(x1, y1, x2, y2, brush) {
        NumPut("Int", x1, "Int", y1, "Int", x2, "Int", y2, rc)
        DllCall("FillRect", "Ptr", mdc, "Ptr", rc, "Ptr", brush)
    }
    R(0, 0, dw, dh, br["black"])
    if mono {
        ; An 8-bit grey-palette copy turns the band grey in one native call.
        gi := Buffer(40 + 1024, 0)
        NumPut("UInt", 40, gi, 0), NumPut("Int", dw, gi, 4), NumPut("Int", -bandH, gi, 8)
        NumPut("UShort", 1, gi, 12), NumPut("UShort", 8, gi, 14), NumPut("UInt", 256, gi, 32)
        Loop 256
            NumPut("UInt", (A_Index - 1) * 0x010101, gi, 36 + A_Index * 4)
        gdc := DllCall("CreateCompatibleDC", "Ptr", sdc, "Ptr")
        gbm := DllCall("CreateDIBSection", "Ptr", gdc, "Ptr", gi, "UInt", 0, "Ptr*", &gbits := 0, "Ptr", 0, "UInt", 0, "Ptr")
        gold := DllCall("SelectObject", "Ptr", gdc, "Ptr", gbm, "Ptr")
        DllCall("SetStretchBltMode", "Ptr", gdc, "Int", 3)
        DllCall("StretchBlt", "Ptr", gdc, "Int", 0, "Int", 0, "Int", dw, "Int", bandH
            , "Ptr", b.dc, "Int", 0, "Int", 0, "Int", b.w, "Int", b.h, "UInt", 0x00CC0020)
        DllCall("BitBlt", "Ptr", mdc, "Int", 0, "Int", 0, "Int", dw, "Int", bandH, "Ptr", gdc, "Int", 0, "Int", 0, "UInt", 0x00CC0020)
        DllCall("SelectObject", "Ptr", gdc, "Ptr", gold)
        DllCall("DeleteObject", "Ptr", gbm)
        DllCall("DeleteDC", "Ptr", gdc)
    } else {
        DllCall("SetStretchBltMode", "Ptr", mdc, "Int", 3)
        DllCall("StretchBlt", "Ptr", mdc, "Int", 0, "Int", 0, "Int", dw, "Int", bandH
            , "Ptr", b.dc, "Int", 0, "Int", 0, "Int", b.w, "Int", b.h, "UInt", 0x00CC0020)
    }
    y0 := bandH + 2
    if IsObject(d) {
        names := ["other", "track", "bar", "fish"]
        x := 0
        while (x < dw) {
            c := NumGet(b.lab, Min(b.w - 1, x * b.w // dw), "UChar")
            x2 := x + 1
            while (x2 < dw && NumGet(b.lab, Min(b.w - 1, x2 * b.w // dw), "UChar") = c)
                x2++
            R(x, y0, x2, y0 + stripH, br[names[(c > 3 ? 0 : c) + 1]])
            x := x2
        }
        if d.bar {
            x1 := d.bl * dw // b.w, x2 := (d.br + 1) * dw // b.w
            for e in [[x1, 0, x2, 2], [x1, bandH - 2, x2, bandH], [x1, 0, x1 + 2, bandH], [x2 - 2, 0, x2, bandH]]
                R(e[1], e[2], e[3], e[4], br["white"])
            for e in [[x1 + 2, 2, x2 - 2, 3], [x1 + 2, bandH - 3, x2 - 2, bandH - 2], [x1 + 2, 2, x1 + 3, bandH - 2], [x2 - 3, 2, x2 - 2, bandH - 2]]
                R(e[1], e[2], e[3], e[4], br["black"])
        }
        if d.fish {
            fx := Round(d.fx * dw / b.w), y := 0
            while (y < bandH) {
                R(fx - 1, y, fx + 2, Min(bandH, y + 3), br[Mod(y // 3, 2) ? "black" : "white"])
                y += 3
            }
        }
    } else {
        R(0, y0, dw, y0 + stripH, br["none"])
    }
    DllCall("SelectObject", "Ptr", mdc, "Ptr", old)
    DllCall("DeleteDC", "Ptr", mdc)
    DllCall("ReleaseDC", "Ptr", 0, "Ptr", sdc)
    return hbm
}

; A standalone copy of the band's current image, for saving later.
BandCopy(b) {
    bi := Buffer(40, 0)
    NumPut("UInt", 40, bi, 0), NumPut("Int", b.w, bi, 4), NumPut("Int", -b.h, bi, 8)
    NumPut("UShort", 1, bi, 12), NumPut("UShort", 32, bi, 14)
    sdc := DllCall("GetDC", "Ptr", 0, "Ptr")
    mdc := DllCall("CreateCompatibleDC", "Ptr", sdc, "Ptr")
    hbm := DllCall("CreateDIBSection", "Ptr", mdc, "Ptr", bi, "UInt", 0, "Ptr*", &bits := 0, "Ptr", 0, "UInt", 0, "Ptr")
    old := DllCall("SelectObject", "Ptr", mdc, "Ptr", hbm, "Ptr")
    DllCall("BitBlt", "Ptr", mdc, "Int", 0, "Int", 0, "Int", b.w, "Int", b.h, "Ptr", b.dc, "Int", 0, "Int", 0, "UInt", 0x00CC0020)
    DllCall("SelectObject", "Ptr", mdc, "Ptr", old)
    DllCall("DeleteDC", "Ptr", mdc)
    DllCall("ReleaseDC", "Ptr", 0, "Ptr", sdc)
    return hbm
}

;------------------------------------------------------------------------------
; Noiseform's reel, read by its shape. Its glow follows the fish and its bar
; turns dark and see-through when the fish leaves it, so colours don't hold.
; What does: the bar is a box whose sides are thin black lines running the
; full height of the reel, and the fish is a black capsule that sticks out
; above and below that box. Measured on a real Noiseform reel.
;------------------------------------------------------------------------------
BoxScan(b, geo, predFish := -1, p := 0) {
    barW := p ? p.barW : 0
    w := b.w, cols := b.cols, bits := b.bits, st := b.stride
    none := {bar: false, bl: -1, br: -1, fish: false, fx: -1, cover: 0, n: 0, fishCol: false}
    ; the fish: a black capsule above and below the reel, same place in both
    ; rows (its lower end reads a little wider in the glow)
    off := Max(3, Round(geo.ih * 0.3))
    up := BoxRuns(b, Max(0, geo.m - off), w), dn := BoxRuns(b, Min(b.h - 1, geo.m + geo.ih + off), w)
    fx := -1, fBest := 1e9, tol := Max(3, Round(w * 0.004))
    for u in up
        for v in dn {
            if (Abs(u[1] - v[1]) > tol || Abs(u[2] - v[2]) > Max(4, 0.6 * Max(u[2], v[2])))
                continue
            cen := (u[1] + v[1]) / 2
            sc := Abs(u[2] - v[2]) + (predFish >= 0 ? Abs(cen - predFish) / Max(1, w * 0.05) : 0)
            if (sc < fBest)
                fBest := sc, fx := cen
        }
    none.fish := fx >= 0, none.fx := fx, none.fishCol := fx >= 0
    ; the bar: thin dark runs across the middle rows are candidates for its sides
    maxW := Max(4, Round(w * 0.005)), cands := [], rs := -1, x := 0
    while (x <= w) {
        dark := false
        if (x < w) {
            c := NumGet(cols, x * 4, "UInt")
            dark := ((((c >> 16) & 255) * 2 + ((c >> 8) & 255) * 5 + (c & 255)) >> 3) < 45
        }
        if dark {
            if (rs < 0)
                rs := x
        } else if (rs >= 0) {
            cx := (rs + x - 1) // 2
            if (x - rs <= maxW && cx > w * 0.01 && cx < w * 0.99)    ; not the track's own end caps
                cands.Push(cx)
            rs := -1
        }
        x++
    }
    if (cands.Length < 1 || cands.Length > 40)
        return none
    ; 2. how tall each is: the sides run the full height of the box
    spans := []
    for cx in cands
        spans.Push(BoxSpan(b, cx, geo.r2))
    ; Both sides must cover the reel box's rows top to bottom (the arrows
    ; fill only the middle). A side next to a dark area can read taller than
    ; it is, so heights aren't compared; the width closest to the bar's wins.
    want := barW ? barW * w : w * 0.30
    best := 1e9, bi := 0, bj := 0
    for i, a in spans {
        if (a[1] > geo.m + 2 || a[2] < geo.m + geo.ih - 2)
            continue
        for j, z in spans {
            if (j <= i || z[1] > geo.m + 2 || z[2] < geo.m + geo.ih - 2)
                continue
            gap := cands[j] - cands[i]
            lo := barW ? (barW - 0.08) * w : w * 0.22, hi := barW ? (barW + 0.08) * w : w * 0.40
            if (gap < lo || gap > hi)
                continue
            sc := Abs(gap - want)
            if (sc < best)
                best := sc, bi := i, bj := j
        }
    }
    ; One side hidden (in the dark state a zone can cover it): once the reel
    ; is running, the bar's width and last place are known, so the other
    ; side is one bar-width away, on whichever side keeps it near its last place.
    if (!bi && p && barW && p.HasOwnProp("boxPrev") && p.boxPrev >= 0) {
        bw := barW * w, bestD := w * 0.15
        for i, a in spans {
            if (a[1] > geo.m + 2 || a[2] < geo.m + geo.ih - 2)
                continue
            for o in [[cands[i], cands[i] + bw], [cands[i] - bw, cands[i]]] {
                if (o[1] < -2 || o[2] > w + 1)
                    continue
                dd := Abs((o[1] + o[2]) / 2 - p.boxPrev)
                if (dd < bestD)
                    bestD := dd, bl := Round(o[1]) + 2, br := Round(o[2]) - 2, bi := -1
            }
        }
    }
    if !bi
        return none
    if (bi > 0)
        bl := cands[bi] + 2, br := cands[bj] - 2
    if p
        p.boxPrev := (bl + br) / 2
    return {bar: true, bl: bl, br: br, fish: fx >= 0, fx: fx, cover: 1, n: br - bl + 1, fishCol: fx >= 0}
}

; Top and bottom rows of the black line through (x, y), bridging tiny gaps.
BoxSpan(b, x, y) {
    bits := b.bits, st := b.stride, o := x * 4, top := y, bot := y, t := y
    while (t > 0) {
        t--
        c := NumGet(bits, t * st + o, "UInt")
        if (((((c >> 16) & 255) * 2 + ((c >> 8) & 255) * 5 + (c & 255)) >> 3) < 45)
            top := t
        else if (top - t > 2)
            break
    }
    t := y
    while (t < b.h - 1) {
        t++
        c := NumGet(bits, t * st + o, "UInt")
        if (((((c >> 16) & 255) * 2 + ((c >> 8) & 255) * 5 + (c & 255)) >> 3) < 45)
            bot := t
        else if (t - bot > 2)
            break
    }
    return [top, bot]
}

; Dark runs of fish width along row y: [[centre, width], ...].
BoxRuns(b, y, w) {
    bits := b.bits, o := y * b.stride, runs := [], rs := -1, x := 0
    lo := Max(3, Round(w * 0.004)), hi := Max(8, Round(w * 0.025))
    while (x <= w) {
        dark := false
        if (x < w) {
            c := NumGet(bits, o + x * 4, "UInt")
            dark := ((((c >> 16) & 255) * 2 + ((c >> 8) & 255) * 5 + (c & 255)) >> 3) < 45
        }
        if dark {
            if (rs < 0)
                rs := x
        } else if (rs >= 0) {
            n := x - rs
            if (n >= lo && n <= hi)
                runs.Push([rs + (n - 1) / 2, n])
            rs := -1
        }
        x++
    }
    return runs
}


;==============================================================================
; Extras: logo graphics, auto totems, Sovereign recharge, Discord alerts and
; auto-reconnect.
;==============================================================================

;------------------------------------------------------------------------------
; GDI+ for the logo, icons and PNG snapshots
;------------------------------------------------------------------------------
class Gdip {
    static token := 0, streams := []
    static Start() {
        if this.token
            return true
        DllCall("LoadLibrary", "Str", "gdiplus", "Ptr")
        si := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
        NumPut("UInt", 1, si, 0)
        if DllCall("gdiplus\GdiplusStartup", "Ptr*", &tok := 0, "Ptr", si, "Ptr", 0)
            return false
        this.token := tok
        return true
    }
    static Stop() {
        for st in this.streams
            try ObjRelease(st)
        this.streams := []
        if this.token
            DllCall("gdiplus\GdiplusShutdown", "Ptr", this.token), this.token := 0
    }
}

; Decodes base64 PNG data into a GDI+ bitmap. Its stream stays alive with it.
GpFromBase64(b64) {
    if !Gdip.Start()
        return 0
    if !DllCall("crypt32\CryptStringToBinary", "Str", b64, "UInt", 0, "UInt", 1, "Ptr", 0, "UInt*", &n := 0, "Ptr", 0, "Ptr", 0)
        return 0
    buf := Buffer(n)
    DllCall("crypt32\CryptStringToBinary", "Str", b64, "UInt", 0, "UInt", 1, "Ptr", buf, "UInt*", &n, "Ptr", 0, "Ptr", 0)
    st := DllCall("shlwapi\SHCreateMemStream", "Ptr", buf, "UInt", n, "Ptr")
    if !st
        return 0
    bmp := 0
    DllCall("gdiplus\GdipCreateBitmapFromStream", "Ptr", st, "Ptr*", &bmp)
    Gdip.streams.Push(st)
    return bmp
}

; A scaled copy of a GDI+ bitmap as an HBITMAP over a solid background.
GpScaled(src, w, h, bgRGB := 0) {
    if !src
        return 0
    DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", w, "Int", h, "Int", 0, "Int", 0x26200A, "Ptr", 0, "Ptr*", &dst := 0)
    DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", dst, "Ptr*", &g := 0)
    DllCall("gdiplus\GdipSetInterpolationMode", "Ptr", g, "Int", 7)
    DllCall("gdiplus\GdipSetPixelOffsetMode", "Ptr", g, "Int", 4)
    DllCall("gdiplus\GdipGraphicsClear", "Ptr", g, "UInt", 0xFF000000 | bgRGB)
    DllCall("gdiplus\GdipGetImageWidth", "Ptr", src, "UInt*", &sw := 0)
    DllCall("gdiplus\GdipGetImageHeight", "Ptr", src, "UInt*", &sh := 0)
    DllCall("gdiplus\GdipDrawImageRectRectI", "Ptr", g, "Ptr", src, "Int", 0, "Int", 0, "Int", w, "Int", h
        , "Int", 0, "Int", 0, "Int", sw, "Int", sh, "Int", 2, "Ptr", 0, "Ptr", 0, "Ptr", 0)
    DllCall("gdiplus\GdipDeleteGraphics", "Ptr", g)
    DllCall("gdiplus\GdipCreateHBITMAPFromBitmap", "Ptr", dst, "Ptr*", &hbm := 0, "UInt", 0xFF000000 | bgRGB)
    DllCall("gdiplus\GdipDisposeImage", "Ptr", dst)
    return hbm
}

; An icon of the app tile at `px` pixels, for the tray and title bar.
GpIcon(src, px) {
    if !src
        return 0
    DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", px, "Int", px, "Int", 0, "Int", 0x26200A, "Ptr", 0, "Ptr*", &dst := 0)
    DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", dst, "Ptr*", &g := 0)
    DllCall("gdiplus\GdipSetInterpolationMode", "Ptr", g, "Int", 7)
    DllCall("gdiplus\GdipGraphicsClear", "Ptr", g, "UInt", 0)
    DllCall("gdiplus\GdipGetImageWidth", "Ptr", src, "UInt*", &sw := 0)
    DllCall("gdiplus\GdipGetImageHeight", "Ptr", src, "UInt*", &sh := 0)
    DllCall("gdiplus\GdipDrawImageRectRectI", "Ptr", g, "Ptr", src, "Int", 0, "Int", 0, "Int", px, "Int", px
        , "Int", 0, "Int", 0, "Int", sw, "Int", sh, "Int", 2, "Ptr", 0, "Ptr", 0, "Ptr", 0)
    DllCall("gdiplus\GdipDeleteGraphics", "Ptr", g)
    DllCall("gdiplus\GdipCreateHICONFromBitmap", "Ptr", dst, "Ptr*", &hicon := 0)
    DllCall("gdiplus\GdipDisposeImage", "Ptr", dst)
    return hicon
}

; Saves an HBITMAP as a PNG file. True on success.
SavePng(hbm, path) {
    if (!hbm || !Gdip.Start())
        return false
    bmp := 0
    DllCall("gdiplus\GdipCreateBitmapFromHBITMAP", "Ptr", hbm, "Ptr", 0, "Ptr*", &bmp)
    if !bmp
        return false
    clsid := Buffer(16)
    DllCall("ole32\CLSIDFromString", "WStr", "{557CF406-1A04-11D3-9A73-0000F81EF32E}", "Ptr", clsid)
    r := DllCall("gdiplus\GdipSaveImageToFile", "Ptr", bmp, "WStr", path, "Ptr", clsid, "Ptr", 0)
    DllCall("gdiplus\GdipDisposeImage", "Ptr", bmp)
    return r = 0
}

LogoImage(which) {
    static cache := Map()
    if !cache.Has(which)
        cache[which] := GpFromBase64(LogoData(which))
    return cache[which]
}

; The tray and title-bar icon: the fish on a black tile.
ApplyAppIcon(hwnd := 0) {
    static small := 0, big := 0
    if !small
        small := GpIcon(LogoImage("icon"), 16), big := GpIcon(LogoImage("icon"), 32)
    if !small
        return
    try TraySetIcon("HICON:*" big)
    if hwnd {
        SendMessage(0x80, 0, small, , "ahk_id " hwnd)
        SendMessage(0x80, 1, big, , "ahk_id " hwnd)
    }
}

;------------------------------------------------------------------------------
; Auto totems. Each entry: name, hotbar key, how often, whether it needs night.
; Stored in [Totems] as  1=Aurora|5|20|1|1  (name|key|minutes|on|night).
;------------------------------------------------------------------------------

LoadTotems() {
    Totems.Length := 0
    try section := IniRead(IniPath, "Totems")
    catch
        return
    Loop Parse, section, "`n", "`r" {
        if !RegExMatch(A_LoopField, "^\d+=(.*)$", &m)
            continue
        f := StrSplit(m[1], "|")
        if (f.Length < 5 || Trim(f[1]) = "" || Totems.Length >= TOTEM_MAX)
            continue
        Totems.Push({name: f[1], slot: f[2], every: Clamp(Round(f[3] + 0), 1, 240), on: f[4] ? 1 : 0, night: f[5] ? 1 : 0, next: 0})
    }
}

SaveTotems() {
    if NoSave
        return
    try IniDelete(IniPath, "Totems")
    for i, t in Totems
        try IniWrite(Format("{}|{}|{}|{}|{}", RegExReplace(t.name, "[|=\r\n]", " "), t.slot, t.every, t.on, t.night), IniPath, "Totems", i)
}

AddTotem(name, *) {
    if (Totems.Length >= TOTEM_MAX)
        return SetDetail("Up to " TOTEM_MAX " totems can be scheduled.")
    night := 0
    for p in TotemPresets
        if (p[1] = name)
            night := p[2]
    Totems.Push({name: name, slot: "", every: name = "Sundial" ? 10 : 15, on: 1, night: night, next: 0})
    SaveTotems()
    try TotemsChanged()
    SetDetail("Added the " name " Totem. Set its hotbar key so the macro can use it.")
}

RemoveTotem(i, *) {
    if (i < 1 || i > Totems.Length)
        return
    name := Totems[i].name
    Totems.RemoveAt(i)
    SaveTotems()
    try TotemsChanged()
    SetDetail("Removed the " name " Totem from the schedule.")
}

; On start every totem is due within a few seconds, staggered.
ScheduleTotems() {
    for i, t in Totems
        t.next := A_TickCount + 4000 + (i - 1) * 3000
}

TotemDue() {
    if !Cfg["TotemAuto"]
        return false
    for t in Totems
        if (t.on && t.slot != "" && A_TickCount >= t.next)
            return true
    return false
}

RunTotems() {
    for t in Totems {
        if !Running
            return
        if !(t.on && t.slot != "" && A_TickCount >= t.next)
            continue
        if (t.night && !IsNight()) {
            sd := 0
            for s in Totems
                if (s.name = "Sundial" && s.slot != "")
                    sd := s
            if (Cfg["TotemSundial"] && sd) {
                UseTotem(sd, "to make it night for the " t.name " Totem")
                sd.next := A_TickCount + sd.every * 60000
                Nap(6000)
            }
            if !IsNight() {
                t.next := A_TickCount + 120000
                LogEvent("The " t.name " Totem waits for night (sky level " SkyLevel() ")")
                continue
            }
        }
        UseTotem(t)
        t.next := A_TickCount + t.every * 60000
    }
}

UseTotem(t, why := "") {
    SetPhase("job", "Using the " t.name " Totem", why != "" ? "Used " why "." : "Hotbar key " KeyName(t.slot) ", then back to the rod.")
    ReleaseMouse()
    MouseToCenter()
    Send "{" t.slot "}"
    Nap(500)
    Click()
    Nap(Cfg["TotemWait"])
    Send "{" Cfg["RodKey"] "}"
    Nap(500)
    LogEvent("Used the " t.name " Totem")
    Alert("totem", "Used the **" t.name " Totem**" (why != "" ? " " why : "") ".")
}

; Average brightness (0-255) of the sky: a grid of points across the top of
; the Roblox window. Lower means darker.
SkyLevel() {
    cr := RobloxHwnd ? ClientRect(RobloxHwnd) : 0
    if !cr
        return -1
    sum := 0, n := 0, hr := Hud.Rect()          ; the small panel isn't sky
    for fy in [0.03, 0.06, 0.09] {
        Loop 8 {
            x := cr.x + Round(cr.w * (A_Index - 0.5) / 8), y := cr.y + Round(cr.h * fy)
            if (hr && x >= hr.x && x < hr.x + hr.w && y >= hr.y && y < hr.y + hr.h)
                continue
            c := PixelGetColor(x, y)
            sum += (((c >> 16) & 255) * 2 + ((c >> 8) & 255) * 5 + (c & 255)) / 8, n++
        }
    }
    return n ? Round(sum / n) : -1
}

IsNight() => (lv := SkyLevel()) >= 0 && lv < Cfg["NightLevel"]

UseTotemsNow(*) {
    global Running, RobloxHwnd
    if (Running || AqManual)
        return SetDetail("Stop fishing first; totems run by themselves between catches.")
    if !(RobloxHwnd := FindRoblox())
        return SetPhase("error", "Roblox isn't open", "Open Fisch first, then try again.")
    try WinActivate("ahk_id " RobloxHwnd)
    Sleep 300
    Running := true
    try {
        for t in Totems
            t.next := 0
        RunTotems()
    } finally {
        Running := false
        SetPhase("idle", "Totems used", IdleHint())
    }
}

;------------------------------------------------------------------------------
; Sovereign recharge. A Sovereign enchant drains as you fish. Every N reels
; this opens the inventory, searches for a plain Enchant Relic (no mutation,
; so mutated relics are never spent), holds it, and clicks Enchant Rod and
; Confirm, once per relic. Every step checks the game responded: the
; inventory opened, the confirm box appeared, the confirm box closed. No
; setup: the buttons' spots come from Fisch's own layout (UiSpots).
;------------------------------------------------------------------------------
SovereignDue() => Cfg["SovAuto"] && SovReels >= Cfg["SovEvery"]

; A spot in Fisch's interface, in screen pixels, for this Roblox window.
UiSpot(name, cr) {
    s := UiSpots[name]
    return {x: cr.x + Round(cr.w / 2 + s[1] * cr.h), y: cr.y + Round(s[2] * cr.h)}
}

RunSovereign() {
    global SovReels, SovLast
    SovReels := 0
    cr := RobloxHwnd ? ClientRect(RobloxHwnd) : 0
    if !cr
        return
    er := UiSpot("enchantRod", cr), sr := UiSpot("search", cr), fi := UiSpot("firstItem", cr), cf := UiSpot("confirm", cr)
    SetPhase("job", "Recharging Sovereign power", "Inventory, plain relic, Enchant Rod, Confirm.")
    ReleaseMouse()
    done := 0, problem := "", opened := false
    ref := PixelGetColor(er.x, er.y)
    Send "{" Cfg["SovInvKey"] "}"
    if !WaitPixelChange(er.x, er.y, ref, Max(1500, Cfg["SovOpenWait"] * 3)) {
        problem := "the inventory didn't open"
    } else {
        opened := true
        Nap(Cfg["SovOpenWait"] // 3)
        ; find a relic with no mutation
        typed := SearchInventory(sr, cr, "mutation:no Enchant Relic")
        if !typed
            problem := "couldn't type into the inventory search"
        Loop (typed ? Cfg["SovCount"] : 0) {
            if !Running
                break
            Click(fi.x, fi.y)                       ; hold the first plain relic
            Nap(Cfg["SovStep"])
            ref := PixelGetColor(cf.x, cf.y)
            Click(er.x, er.y)                       ; Enchant Rod
            if !WaitPixelChange(cf.x, cf.y, ref, 3500) {
                problem := "Enchant Rod didn't open the confirm box (out of plain relics?)"
                break
            }
            Nap(250)
            dlg := PixelGetColor(cf.x, cf.y)
            Click(cf.x, cf.y)                       ; Confirm
            if !WaitPixelChange(cf.x, cf.y, dlg, 3000) {
                problem := "the confirm box didn't close"
                break
            }
            done++
            Nap(Cfg["SovStep"])
        }
    }
    if opened
        Send "{" Cfg["SovInvKey"] "}"              ; close the inventory
    Nap(400)
    Send "{" Cfg["RodKey"] "}"
    Nap(500)
    MouseToCenter()
    result := done " of " Cfg["SovCount"] " recharge" (Cfg["SovCount"] = 1 ? "" : "s") (problem != "" ? ", " problem : "")
    SovLast := FormatTime(, "HH:mm") ", " result
    LogEvent("Sovereign recharge: " result)
    Alert(problem != "" ? "error" : "sovereign", "Sovereign recharge: " result ".", problem != "")
    try PaintSovStatus()
}

WaitPixelChange(x, y, ref, ms) {
    t0 := A_TickCount
    while (A_TickCount - t0 < ms) {
        if (ColDist(PixelGetColor(x, y), ref) > 40)
            return true
        Sleep 50
    }
    return false
}

RechargeNow(*) {
    global Running, SovReels, RobloxHwnd
    if (Running || AqManual)
        return SetDetail("Stop fishing first; recharges run by themselves between catches.")
    if !(RobloxHwnd := FindRoblox())
        return SetPhase("error", "Roblox isn't open", "Open Fisch first, then try again.")
    try WinActivate("ahk_id " RobloxHwnd)
    Sleep 300
    Running := true
    try RunSovereign()
    finally {
        Running := false
        SetPhase("idle", "Recharge finished", SovLast)
        try PaintSovStatus()
    }
}

;------------------------------------------------------------------------------
; Discord alerts through a webhook. Messages queue and send in the
; background, so the reel loop never waits on the network.
;------------------------------------------------------------------------------

HookUrlOk(url) {
    return RegExMatch(url, "i)^https://(canary\.|ptb\.)?(discord|discordapp)\.com/api/webhooks/\d+/[\w-]+") || (HookAllowLocal && RegExMatch(url, "^http://127\.0\.0\.1:\d+/"))
}

Alert(kind, msg, shot := false) {
    global HookQueue
    if (Cfg["HookUrl"] = "" || !HookUrlOk(Cfg["HookUrl"]))
        return
    if (HookKinds.Has(kind) && !Cfg[HookKinds[kind]])
        return
    if (HookQueue.Length >= 20)
        HookQueue.RemoveAt(1)
    HookQueue.Push({kind: kind, msg: msg, shot: shot && Cfg["HookShots"], when: A_NowUTC})
    SetTimer(HookPump, -20)
}

HookPump() {
    global HookReq, HookBusy, HookLast, HookItem
    if (HookBusy || !HookQueue.Length)
        return
    it := HookQueue.RemoveAt(1), HookItem := it
    body := HookBody(it, &ctype)
    try {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.Open("POST", Cfg["HookUrl"], true)
        req.SetRequestHeader("Content-Type", ctype)
        req.SetTimeouts(5000, 5000, 10000, 15000)
        req.Send(body)
        HookReq := req, HookBusy := A_TickCount
        SetTimer(HookPoll, 100)
    } catch as e {
        HookLast := "Couldn't reach Discord: " e.Message
        try PaintHookStatus()
    }
}

HookPoll() {
    global HookReq, HookBusy, HookLast
    ; Status throws until the answer arrives. (WaitForResponse(0) can miss a
    ; finished request, so it isn't used.) A failed connection never
    ; answers, so it ends in the timeout.
    st := 0
    try st := HookReq.Status
    if !st {
        if (A_TickCount - HookBusy > 20000) {
            try HookReq.Abort()
            HookLast := "Couldn't reach Discord (no answer in 20 s)"
            HookDone(1500)
        }
        return
    }
    if (st = 429) {
        ; rate limited: put the message back at the front and wait as asked
        wait := 2000
        try wait := Max(500, Round(HookReq.GetResponseHeader("Retry-After") * 1000))
        if (IsObject(HookItem) && (HookItem.tries := (HookItem.HasOwnProp("tries") ? HookItem.tries : 0) + 1) <= 3)
            HookQueue.InsertAt(1, HookItem)
        HookLast := "Discord asked to slow down; retrying"
        return HookDone(wait)
    }
    HookLast := (st >= 200 && st < 300) ? "Sent " FormatTime(, "HH:mm:ss") : "Discord refused the message (HTTP " st ")"
    HookDone(1100)
}

HookDone(nextIn) {
    global HookReq, HookBusy
    HookReq := 0, HookBusy := 0
    SetTimer(HookPoll, 0)
    try PaintHookStatus()
    if HookQueue.Length
        SetTimer(HookPump, -nextIn)
}

; JSON (or multipart with a screenshot) for one alert, as UTF-8 bytes.
HookBody(it, &ctype) {
    title := HookTitles.Has(it.kind) ? HookTitles[it.kind] : "Fisch macro"
    user := RegExReplace(Cfg["HookUser"], "\D")
    ping := (user != "" && (it.kind = "error" || it.kind = "disconnect")) ? "<@" user ">" : ""
    rod := IsObject(CurRod) ? CurRod.name : "no rod yet"
    stamp := FormatTime(it.when, "yyyy-MM-dd'T'HH:mm:ss") ".000Z"
    embed := '{"title":' JsonStr(title) ',"description":' JsonStr(it.msg) ',"color":' (it.kind = "error" || it.kind = "disconnect" ? 16777215 : 9211020)
        . ',"fields":[{"name":"Casts","value":"' Stats.casts '","inline":true},{"name":"Reels","value":"' Stats.reels '","inline":true},{"name":"Rod","value":' JsonStr(rod) ',"inline":true}]'
        . ',"footer":{"text":' JsonStr(APP_NAME " " APP_VER) '},"timestamp":"' stamp '"'
    png := 0
    if it.shot {
        path := A_Temp "\fisch_alert.png"
        if (cr := RobloxHwnd ? ClientRect(RobloxHwnd) : 0) {
            hbm := CaptureBitmap(cr.x, cr.y, cr.w, cr.h)
            if SavePng(hbm, path)
                png := FileRead(path, "RAW")
            DllCall("DeleteObject", "Ptr", hbm)
        }
    }
    if png
        embed .= ',"image":{"url":"attachment://roblox.png"}'
    embed .= "}"
    json := '{"username":"FISCHXR","content":' JsonStr(ping) ',"embeds":[' embed ']'
        . (ping != "" ? ',"allowed_mentions":{"users":["' user '"]}' : ',"allowed_mentions":{"parse":[]}') "}"
    if !png {
        ctype := "application/json"
        return Utf8Array(json)
    }
    bd := "fischmacro" A_TickCount
    ctype := "multipart/form-data; boundary=" bd
    head := "--" bd "`r`nContent-Disposition: form-data; name=`"payload_json`"`r`nContent-Type: application/json`r`n`r`n" json
        . "`r`n--" bd "`r`nContent-Disposition: form-data; name=`"files[0]`"; filename=`"roblox.png`"`r`nContent-Type: image/png`r`n`r`n"
    tail := "`r`n--" bd "--`r`n"
    hn := StrPut(head, "UTF-8") - 1, tn := StrPut(tail, "UTF-8") - 1
    all := Buffer(hn + png.Size + tn)
    StrPut(head, all, hn, "UTF-8")
    DllCall("RtlMoveMemory", "Ptr", all.Ptr + hn, "Ptr", png, "UPtr", png.Size)
    StrPut(tail, all.Ptr + hn + png.Size, tn, "UTF-8")
    return BytesArray(all, all.Size)
}

Utf8Array(s) {
    n := StrPut(s, "UTF-8") - 1
    b := Buffer(Max(1, n))
    StrPut(s, b, n, "UTF-8")
    return BytesArray(b, n)
}

BytesArray(buf, n) {
    arr := ComObjArray(0x11, n)
    pv := NumGet(ComObjValue(arr), 8 + A_PtrSize, "Ptr")
    DllCall("RtlMoveMemory", "Ptr", pv, "Ptr", buf, "UPtr", n)
    return arr
}

JsonStr(s) {
    out := '"'
    Loop Parse, s {
        c := A_LoopField, o := Ord(c)
        if (c = '"')
            out .= '\"'
        else if (c = "\")
            out .= "\\"
        else if (o = 10)
            out .= "\n"
        else if (o = 13)
            out .= "\r"
        else if (o = 9)
            out .= "\t"
        else if (o < 32 || o > 126)
            out .= Format("\u{:04x}", o)
        else
            out .= c
    }
    return out '"'
}

SendTestAlert(*) {
    global HookLast
    if (Cfg["HookUrl"] = "") {
        HookLast := "Paste your webhook link first"
        return PaintHookStatus()
    }
    if !HookUrlOk(Cfg["HookUrl"]) {
        HookLast := "That isn't a Discord webhook link"
        return PaintHookStatus()
    }
    HookLast := "Sending…"
    PaintHookStatus()
    Alert("test", "Alerts are working. You'll hear from this channel when fishing stops, errors or disconnects.", Cfg["HookShots"] && RobloxHwnd)
}

SummaryTick() {
    if !Running
        return
    mins := Round((A_TickCount - Stats.start) / 60000)
    rate := mins ? Round(Stats.reels * 60 / mins) : 0
    Alert("summary", Format("{} casts and {} reels in {} min, about {} reels an hour. {} missed bites.", Stats.casts, Stats.reels, mins, rate, Stats.misses))
}

;------------------------------------------------------------------------------
; Auto-reconnect. Watches Roblox's own log for a lost connection (ignoring
; teleports, which also disconnect briefly), or the window closing, then
; closes Roblox, opens the rejoin link and resumes fishing.
;------------------------------------------------------------------------------
RobloxLogDirs() {
    la := EnvGet("LOCALAPPDATA")
    return [la "\Roblox\logs", la "\Packages\ROBLOXCORPORATION.ROBLOX_55nm5eh3cm0pr\LocalState\logs"]
}

NewestRobloxLog() {
    best := "", bt := 0
    for dir in (LogDirOverride != "" ? [LogDirOverride] : RobloxLogDirs())
        Loop Files, dir "\*.log" {
            t := A_LoopFileTimeModified + 0       ; YYYYMMDDHH24MISS as a number
            if (t > bt)
                bt := t, best := A_LoopFileFullPath
        }
    return best
}

; Reads what Roblox has written since the last look. A disconnect line with
; no teleport or join around it, and no rejoin within LogConfirmMs (12 s), is
; a real drop.
CheckRobloxLog() {
    global LogFile, LogPos, LogPending, LogJoinT, LogTeleT, LogLastLine
    static lastScan := 0
    if (A_TickCount - lastScan > 20000 || LogFile = "") {
        lastScan := A_TickCount
        f := NewestRobloxLog()
        if (f != LogFile) {
            LogFile := f, LogPending := 0
            LogPos := -1
        }
    }
    if (LogFile = "")
        return ""
    try {
        fo := FileOpen(LogFile, "r", "UTF-8-RAW")
        size := fo.Length
        if (LogPos < 0 || size < LogPos)
            LogPos := size          ; start at the end: old history doesn't count
        fo.Pos := LogPos
        text := fo.Read()
        LogPos := fo.Pos
        fo.Close()
    } catch
        return ""
    now := A_TickCount
    Loop Parse, text, "`n", "`r" {
        ln := A_LoopField
        if (ln = "")
            continue
        if RegExMatch(ln, "i)initiateTeleport|teleporting|TeleportService")
            LogTeleT := now
        else if RegExMatch(ln, "i)! Joining game|Connection accepted from|serverId:|Replicator created")
            LogJoinT := now
        else if RegExMatch(ln, "i)Lost connection with reason|Disconnect reason|Sending disconnect with reason|Client:Disconnect|Connection lost|Time to disconnect replication data|kicked from") {
            LogLastLine := Trim(SubStr(RegExReplace(ln, "^\S+\s*"), 1, 160))
            if (now - LogTeleT > 30000 && !LogPending)
                LogPending := now
        }
    }
    if (LogPending && LogJoinT > LogPending)
        LogPending := 0          ; it came back by itself (a teleport or server hop)
    if (LogPending && now - LogPending >= LogConfirmMs) {
        LogPending := 0
        return LogLastLine != "" ? "Roblox log: " LogLastLine : "Roblox reported a lost connection"
    }
    return ""
}

WatchConnection() {
    if (!Running || !Cfg["AutoReconnect"] || ReconnectWhy != "")
        return
    if (RobloxHwnd && !WinExist("ahk_id " RobloxHwnd))
        return FlagDisconnect("The Roblox window closed")
    if ((why := CheckRobloxLog()) != "")
        FlagDisconnect(why)
}

FlagDisconnect(why) {
    global ReconnectWhy
    if (ReconnectWhy = "")
        ReconnectWhy := why
}

ReconnectDue() => Cfg["AutoReconnect"] && ReconnectWhy != ""

; Turns whatever link the user pasted into something Windows can open.
RejoinTarget() {
    link := Trim(Cfg["RejoinLink"])
    if (link = "")
        link := Defaults["RejoinLink"]
    if RegExMatch(link, "i)^roblox(-player)?:")
        return link
    if RegExMatch(link, "^\d+$")
        return "roblox://experiences/start?placeId=" link
    if RegExMatch(link, "i)roblox\.com/games/(\d+)", &g) {
        uri := "roblox://experiences/start?placeId=" g[1]
        if RegExMatch(link, "i)privateServerLinkCode=([\w-]+)", &c)
            uri .= "&linkCode=" c[1]
        return uri
    }
    return link                  ; share links open through the browser
}

Reconnect() {
    global ReconnectWhy, RobloxHwnd, ReconnectTimes, LogFile
    why := ReconnectWhy
    ReleaseMouse()
    ; attempts in the last hour
    kept := []
    for t in ReconnectTimes
        if (A_TickCount - t < 3600000)
            kept.Push(t)
    ReconnectTimes := kept
    if (ReconnectTimes.Length >= Cfg["RejoinMax"]) {
        StopMacro("Disconnected. Gave up after " Cfg["RejoinMax"] " rejoins this hour.")
        ReconnectWhy := ""
        return false
    }
    ReconnectTimes.Push(A_TickCount)
    LogEvent("Disconnected: " why)
    Alert("disconnect", "Disconnected: " why ". Rejoining now.", true)
    SetPhase("pause", "Reconnecting", why)
    Loop 3
        try ProcessClose("RobloxPlayerBeta.exe")
    Sleep 2500
    target := RejoinTarget()
    try {
        if IsObject(RejoinHook)
            RejoinHook.Call(target)
        else
            Run(target)
    } catch as e {
        StopMacro("Couldn't open the rejoin link: " e.Message)
        ReconnectWhy := ""
        return false
    }
    SetPhase("pause", "Rejoining Fisch", "Waiting for the Roblox window.")
    t0 := A_TickCount, h := 0
    while (Running && A_TickCount - t0 < 120000) {
        if (h := FindRoblox())
            break
        Sleep 1000
    }
    if !Running
        return false
    if !h {
        LogEvent("Roblox didn't reopen; trying again")
        return true              ; ReconnectWhy is still set, so the loop retries
    }
    RobloxHwnd := h, LogFile := ""
    SetPhase("pause", "Rejoining Fisch", "Giving the game " Cfg["RejoinWait"] " s to load.")
    if !Nap(Cfg["RejoinWait"] * 1000)
        return false
    try WinActivate("ahk_id " h)
    Sleep 500
    if Cfg["RejoinResume"] {
        MouseToCenter()
        Click()
        Sleep 600
        Send "{" Cfg["RodKey"] "}"
        Sleep 700
    }
    ReconnectWhy := ""
    LogEvent("Rejoined after: " why)
    Alert("reconnect", "Rejoined Fisch and resumed fishing. If you spawned away from your spot, fishing may fail until you walk back.", true)
    return true
}

; Reconnect tab: what the watcher can see right now.
ReconnectStatusText() {
    f := NewestRobloxLog()
    if (f = "")
        return "No Roblox log found yet. It appears once Roblox has run."
    SplitPath(f, &name)
    t := FileGetTime(f, "M")
    ago := DateDiff(A_Now, t, "Seconds")
    s := "Watching " name ", updated " (ago < 90 ? ago " s" : Round(ago / 60) " min") " ago."
    if (LogLastLine != "")
        s .= "`nLast disconnect line: " LogLastLine
    return s
}

;------------------------------------------------------------------------------
; Reel-end records: what the macro saw when it decided a reel was over. A
; screenshot of the Roblox window, the reel band when the reel first looked
; gone and at the end, and the last frames' readings. The last ten are kept.
;------------------------------------------------------------------------------
SaveReelSnapshot(b, geo, p, trail, lostHbm, lostAt, reason, dur := 0, good := 0) {
    dir := A_ScriptDir "\Snapshots\Reels"
    try DirCreate(dir)
    stamp := FormatTime(, "yyyy-MM-dd_HH-mm-ss") "_" A_MSec
    cr := RobloxHwnd ? ClientRect(RobloxHwnd) : 0
    if cr {
        hbm := CaptureBitmap(cr.x, cr.y, cr.w, cr.h)
        SavePng(hbm, dir "\" stamp "_window.png")
        DllCall("DeleteObject", "Ptr", hbm)
    }
    hbm := BandCopy(b)
    SavePng(hbm, dir "\" stamp "_band_end.png")
    DllCall("DeleteObject", "Ptr", hbm)
    if lostHbm
        SavePng(lostHbm, dir "\" stamp "_band_lost.png")
    r := APP_NAME " " APP_VER " reel-end record " stamp "`n`n"
        . "Why it ended: " reason "`n"
        . "First looked gone: " (lostAt >= 0 ? lostAt " ms into the reel" : "never") "`n"
        . "Reel length: " dur " ms, frames with the reel seen: " good "`n"
        . Format("Band: {}x{} at {},{} (margin {}, reel height {})", b.w, b.h, geo.x, geo.y, geo.m, geo.ih) "`n"
        . Format("Reel box: {:.4f} {:.4f} {:.4f} {:.4f}", Cfg["ReelX1"], Cfg["ReelY1"], Cfg["ReelX2"], Cfg["ReelY2"]) "`n"
        . (cr ? "Roblox window: " cr.w "x" cr.h "`n" : "")
    if IsObject(p)
        r .= "`nLook: " p.name " (" p.id ")" (p.lib != "" ? ", library " p.lib : "") ", bar " p.barW
            . "`nTrack: " HexJoin(p.track) "`nBar: " HexJoin(p.bar) "`nFish: " HexJoin(p.fish)
            . "`nOutline rows: " p.edgeT " / " p.edgeB "`n"
    r .= "`nLast frames: ms into reel, outline (1 found, 0 missing, -1 not learned), colours fit,`n"
        . "bar (found, left-right), fish (found, x), counted as present, mouse held`n"
    for l in trail
        r .= l "`n"
    try FileAppend(r, dir "\" stamp "_report.txt", "UTF-8")
    ; keep the last ten
    stamps := []
    Loop Files, dir "\*_report.txt"
        stamps.Push(SubStr(A_LoopFileName, 1, 23))
    if (stamps.Length > 10) {
        s := ""
        for t in stamps
            s .= t "`n"
        list := StrSplit(Sort(RTrim(s, "`n")), "`n")
        Loop list.Length - 10 {
            old := list[A_Index]
            Loop Files, dir "\" old "_*.*"
                try FileDelete(A_LoopFileFullPath)
        }
    }
}

;------------------------------------------------------------------------------
; Typing into Fisch's inventory search. Roblox drops keys sent in one burst,
; so each key is held briefly with a gap, the way a person types. First it
; makes sure the box has focus: clearing it (or, if it was empty, typing a
; space) must change what the box shows. If nothing changes, nothing more is
; typed, since letters that miss the box would reach the game as hotkeys.
;------------------------------------------------------------------------------
SearchInventory(sr, cr, query) {
    Click(sr.x, sr.y)
    Nap(300)
    before := BoxSig(sr, cr)
    TypeKeys("{End}{Backspace 40}")
    Nap(200)
    now := BoxSig(sr, cr)
    if !SigDiffers(before, now) {
        TypeKeys("{Space}")
        Nap(200)
        if !SigDiffers(now, BoxSig(sr, cr))
            return false
        TypeKeys("{Backspace}")
    }
    TypeKeys(RegExReplace(query, "[{}^+!#]", "{$0}"))
    TypeKeys("{Enter}")
    Nap(700)
    return true
}

TypeKeys(keys) {
    SetKeyDelay(45, 30)
    SendEvent keys
    SetKeyDelay(10, -1)
}

; Brightness at points along the search box, to tell whether it changed.
BoxSig(sr, cr) {
    v := [], x0 := sr.x - Round(0.07 * cr.h), x1 := sr.x + Round(0.07 * cr.h)
    Loop 16 {
        c := PixelGetColor(x0 + Round((x1 - x0) * (A_Index - 1) / 15), sr.y)
        v.Push((((c >> 16) & 255) * 2 + ((c >> 8) & 255) * 5 + (c & 255)) / 8)
    }
    return v
}

SigDiffers(a, b) {
    n := 0
    for i, x in a
        n += Abs(x - b[i]) > 30
    return n >= 2
}

;------------------------------------------------------------------------------
; Updates and changelog. UpdateUrl points at a small file (update.json):
;   {"version": "4.1.1", "url": "https://.../FischMacro.ahk",
;    "sha256": "<64 hex digits>", "notes": "What changed..."}
; On opening (and on request) the macro reads it; if the version is newer it
; shows the notes and, if you accept, downloads the new file, checks its
; SHA-256 against the manifest, keeps the old file as .bak and restarts.
; The fingerprint is taken with Windows line endings turned into plain ones,
; so it matches however Git stored the file. Whoever controls that address
; controls what gets installed, so it belongs on an account with two-factor
; sign-in.
;------------------------------------------------------------------------------
VersionNewer(a, b) {
    pa := StrSplit(RegExReplace(a, "[^\d.]"), "."), pb := StrSplit(RegExReplace(b, "[^\d.]"), ".")
    Loop Max(pa.Length, pb.Length) {
        x := (A_Index <= pa.Length && pa[A_Index] != "") ? Integer(pa[A_Index]) : 0
        y := (A_Index <= pb.Length && pb[A_Index] != "") ? Integer(pb[A_Index]) : 0
        if (x != y)
            return x > y
    }
    return false
}

HttpGet(url, &status, binary := false, timeoutMs := 8000) {
    req := ComObject("WinHttp.WinHttpRequest.5.1")
    req.Open("GET", url, false)
    req.SetTimeouts(timeoutMs, timeoutMs, timeoutMs, timeoutMs)
    req.SetRequestHeader("Cache-Control", "no-cache")
    req.SetRequestHeader("User-Agent", "FISCHXR/" APP_VER)
    req.Send()
    status := req.Status
    if !binary
        return req.ResponseText
    body := req.ResponseBody
    n := body.MaxIndex() + 1
    buf := Buffer(Max(1, n))
    if (n > 0)
        DllCall("RtlMoveMemory", "Ptr", buf, "Ptr", NumGet(ComObjValue(body), 8 + A_PtrSize, "Ptr"), "UPtr", n)
    return buf
}

; The string value of "key" in a flat JSON object, unescaped.
JsonField(json, key) {
    if !RegExMatch(json, '"' key '"\s*:\s*"((?:[^"\\]|\\.)*)"', &m)
        return ""
    s := m[1], out := "", i := 1, n := StrLen(s)
    while (i <= n) {
        c := SubStr(s, i, 1)
        if (c = "\" && i < n) {
            e := SubStr(s, i + 1, 1)
            if (e = "u")
                out .= Chr(Integer("0x" SubStr(s, i + 2, 4))), i += 6
            else
                out .= (e = "n" ? "`n" : e = "t" ? "`t" : e = "r" ? "" : e), i += 2
        } else
            out .= c, i++
    }
    return out
}

Sha256Hex(buf, n := -1) {
    n := n < 0 ? buf.Size : n, alg := 0, h := 0
    DllCall("bcrypt\BCryptOpenAlgorithmProvider", "Ptr*", &alg, "WStr", "SHA256", "Ptr", 0, "UInt", 0)
    DllCall("bcrypt\BCryptCreateHash", "Ptr", alg, "Ptr*", &h, "Ptr", 0, "UInt", 0, "Ptr", 0, "UInt", 0, "UInt", 0)
    DllCall("bcrypt\BCryptHashData", "Ptr", h, "Ptr", buf, "UInt", n, "UInt", 0)
    out := Buffer(32, 0)
    DllCall("bcrypt\BCryptFinishHash", "Ptr", h, "Ptr", out, "UInt", 32, "UInt", 0)
    DllCall("bcrypt\BCryptDestroyHash", "Ptr", h)
    DllCall("bcrypt\BCryptCloseAlgorithmProvider", "Ptr", alg, "UInt", 0)
    s := ""
    Loop 32
        s .= Format("{:02x}", NumGet(out, A_Index - 1, "UChar"))
    return s
}

; {version, url, sha256, notes} from the update link, or text saying why not.
UpdateInfo() {
    url := Trim(Cfg["UpdateUrl"])
    if (url = "")
        return "Updates aren't set up yet: paste an update link on the Settings tab."
    if !(RegExMatch(url, "i)^https://") || (UpdAllowLocal && RegExMatch(url, "^http://127\.0\.0\.1:\d+/")))
        return "The update link has to start with https://"
    try txt := HttpGet(url, &st)
    catch as e
        return "Couldn't reach the update link."
    if (st != 200)
        return "The update link answered HTTP " st "."
    v := JsonField(txt, "version"), u := JsonField(txt, "url"), h := StrLower(JsonField(txt, "sha256"))
    if (v = "" || u = "" || !RegExMatch(h, "^[0-9a-f]{64}$"))
        return "The update file is missing its version, download link or SHA-256."
    return {version: v, url: u, sha256: h, notes: JsonField(txt, "notes")}
}

UpdateNote(msg) {
    global UpdLast
    UpdLast := msg
    if (UiReady && CurTab = "Settings")
        try UI.desc.Text := msg
}

CheckForUpdate(quiet := false, *) {
    if !quiet
        UpdateNote("Checking for updates…")
    info := UpdateInfo()
    if !IsObject(info) {
        UpdateNote(info)
        if !quiet
            Dialog.Show("Updates", info, "Close")
        return
    }
    if !VersionNewer(info.version, APP_VER) {
        UpdateNote("You have the latest version (" APP_VER ").")
        if !quiet
            Dialog.Show("Updates", "You have the latest version (" APP_VER ").", "Close")
        return
    }
    UpdateNote("Version " info.version " is available.")
    if (quiet && Running)
        return
    Dialog.Show("Update to " info.version "?", (info.notes != "" ? info.notes "`n`n" : "")
        . "The macro downloads it, checks its fingerprint, keeps your current file as a backup and restarts."
        , "Update now", (*) => ApplyUpdate(info), "Later")
}

; Downloads, verifies and installs an update. True when installed.
ApplyUpdate(info, target := "", restart := true) {
    target := target != "" ? target : A_ScriptFullPath
    if Running
        StopMacro()
    try buf := HttpGet(info.url, &st, true, 30000)
    catch
        return UpdateFailed("Couldn't download the update.")
    if (st != 200)
        return UpdateFailed("The download answered HTTP " st ".")
    if (Sha256Hex(NormalizeEol(buf)) != info.sha256)
        return UpdateFailed("The download didn't match its SHA-256 fingerprint, so it wasn't used.")
    head := Buffer(4001, 0)
    DllCall("RtlMoveMemory", "Ptr", head, "Ptr", buf, "UPtr", Min(4000, buf.Size))
    if !InStr(StrGet(head, "UTF-8"), "#Requires AutoHotkey v2")
        return UpdateFailed("The download isn't an AutoHotkey v2 script, so it wasn't used.")
    try {
        f := FileOpen(target ".new", "w")
        f.RawWrite(buf, buf.Size)
        f.Close()
        if FileExist(target)
            FileCopy(target, target ".bak", true)
        FileMove(target ".new", target, true)
    } catch
        return UpdateFailed("Couldn't replace the macro file.")
    UpdateNote("Updated to " info.version ". The previous version is kept as a .bak file.")
    LogEvent("Updated to " info.version)
    if restart
        Reload()
    return true
}

; The bytes with every CR-LF turned into LF, for the fingerprint.
NormalizeEol(buf) {
    sz := buf.Size, out := Buffer(Max(1, sz)), n := 0, i := 0
    while (i < sz) {
        c := NumGet(buf, i, "UChar")
        if !(c = 13 && i + 1 < sz && NumGet(buf, i + 1, "UChar") = 10)
            NumPut("UChar", c, out, n++)
        i++
    }
    out.Size := Max(1, n)
    return out
}

UpdateFailed(msg) {
    UpdateNote(msg)
    try LogEvent("Update: " msg)
    return false
}

; What changed, newest first. Shown once after an upgrade, and on request.
ChangelogText() {
    return "
(
4.2.3
- Check for updates now shows its answer, and hover help shows on every page again.

4.2.2
- Updates now come from the FISCHXR page on GitHub: the macro checks when it opens and asks before installing.

4.2.1
- Noiseform: the reel is read by its shape (the bar's black sides and the fish's black capsule), so it keeps working when the bar turns dark with the fish outside it.

4.2.0
- Now called FISCHXR. Your settings carry over.
- Reads the rod in your hotbar and uses its built-in reel style. Nothing about rods is learned or saved, so no more duplicate rods.
- Verdant Oath: aims the fish at the green zone.
- Pages slide in, the panel slides in from the edge, and the text is plainer.

4.1.0
- New look: tabs down the side and a window about a third smaller.
- While fishing, a small panel in the top-right corner shows what's happening, with a Stop button.
- Simpler pages. Fine-tuning moved under Advanced: Rods, Live, Reel, Timing, More.
- Sovereign recharge types into the inventory search the way a person does, and checks the text arrived before going on.
- Updates: set an update link and the macro can update itself, checking each download's fingerprint.
)"
}

ShowWhatsNew(*) => Dialog.Show("What's new in " APP_VER, ChangelogText(), "Close")

; Once per version: note it, and show What's new after an upgrade.
WhatsNewCheck() {
    last := Cfg["LastVersion"]
    if (last = APP_VER)
        return
    Cfg["LastVersion"] := APP_VER
    Save("LastVersion")
    if (last = "" && !WasExistingIni)
        return                              ; a fresh install
    ShowWhatsNew()
}

;------------------------------------------------------------------------------
; The equipped rod, read from the hotbar. The rod's slot (the rod key) is
; captured, enlarged and read by Windows' built-in text reader (run through
; PowerShell in the background, so fishing never waits on it). Enchant names
; come first on the label and are removed, leaving the rod's own name, which
; picks the built-in reel style.
;------------------------------------------------------------------------------
RodEnchants() {
    static list := 0
    if !list {
        names := "Immortal Might|Magnitude Might|Swift Might|Steady Crown|Glimmering Crown|Stonewake Crown"
            . "|Menacing Spirit|Starforged Spirit|Propensity Spirit|Blood Reckoning|Blessed Song|Sea Overlord"
            . "|Sea Prince|Sea King|Pharaoh's Curse|Pharaohs Curse|Swift|Hasty|Hunter|Lucky|Divine|Breezed|Storming"
            . "|Controlled|Resilient|Quality|Unbreakable|Long|Steady|Blessed|Mutated|Ghastly|Noir|Abyssal|Insight"
            . "|Clever|Scrapper|Wormhole|Sacrificial|Scavenger|Chaotic|Flashline|Chronos|Momentum|Immortal|Mystical"
            . "|Ferocious|Anomalous|Quantum|Piercing|Invincible|Herculean|Overclocked|Tenacity|Tryhard|Wise|Cryogenic"
            . "|Glittered|Vicious|Dune|Restricted|Fractured|Greed|Putrid|Rage|Weak|Wobbly|Tropical|Paradise|Beached"
            . "|Valentine's|Valentines|Cupid|Santa|Gingerbread|Merry|Peppermint|Frightful|Spooky|Eerie|Sanctified"
        s := ""
        for n in StrSplit(names, "|")
            s .= Format("{:03}", 100 - StrLen(n)) "`t" n "`n"
        list := []
        for ln in StrSplit(Sort(RTrim(s, "`n")), "`n")
            list.Push(StrSplit(ln, "`t")[2])       ; longest first
    }
    return list
}

; The rod's name from its hotbar label: the slot number, stack counts and
; weights go, then enchant names are taken off the front. A name is never
; stripped down to just "Rod", so "Lucky Rod" or "Steady Rod" survive.
ParseRodName(text) {
    t := RegExReplace(text, "[\r\n\t]+", " ")
    t := RegExReplace(t, "i)\bx\s?\d+\b", " ")
    t := RegExReplace(t, "i)\b\d+(\.\d+)?\s*k?g\b", " ")
    t := RegExReplace(t, "[^A-Za-z' ]", " ")
    t := Trim(RegExReplace(t, "\s+", " "))
    loop {
        hit := false
        for e in RodEnchants() {
            n := StrLen(e)
            if (StrLen(t) > n + 1 && SubStr(t, 1, n + 1) = e " ") {
                rest := LTrim(SubStr(t, n + 2))
                if (rest = "Rod" || rest = "")
                    continue
                t := rest, hit := true
                break
            }
        }
        if !hit
            break
    }
    return t
}

; Edit distance, for names the text reader got slightly wrong.
EditDistance(a, b) {
    a := StrLower(a), b := StrLower(b), la := StrLen(a), lb := StrLen(b)
    prev := []
    Loop lb + 1
        prev.Push(A_Index - 1)
    Loop la {
        i := A_Index, cur := [i], ca := SubStr(a, i, 1)
        Loop lb {
            j := A_Index
            cur.Push(Min(prev[j + 1] + 1, cur[j] + 1, prev[j] + (ca = SubStr(b, j, 1) ? 0 : 1)))
        }
        prev := cur
    }
    return prev[lb + 1]
}

; The built-in reel style for a rod name ("" means: find it from the reel).
RodLibFor(name) {
    if (name = "")
        return ""
    for lib in RodLib
        if (lib.id != "standard" && EditDistance(name, lib.name) <= Max(1, StrLen(lib.name) // 8))
            return lib.id
    return "standard"
}

; The rod's hotbar slot on screen, from Fisch's layout (measured at 4K).
RodSlotRect(cr, slot) {
    k := Clamp(Integer(slot), 1, 9)
    cx := cr.x + cr.w / 2 + (k - 5) * 0.04798 * cr.h, cy := cr.y + 0.9755 * cr.h, half := 0.0235 * cr.h
    return {x: Round(cx - half), y: Round(cy - half), w: Round(2 * half), h: Round(2 * half)}
}

; Starts reading the equipped rod's name. The result lands in CurRodName.
ReadRodName(announce := false, *) {
    global RodReadBusy, RodReadAt
    if RodReadBusy
        return
    h := (RobloxHwnd && WinExist("ahk_id " RobloxHwnd)) ? RobloxHwnd : FindRoblox()
    cr := h ? ClientRect(h) : 0
    if !cr
        return RodNameDone("", "Roblox isn't open")
    slot := RegExMatch(Cfg["RodKey"], "^[1-9]$") ? Cfg["RodKey"] : 1
    r := RodSlotRect(cr, slot)
    png := A_Temp "\fischxr_rod.png", out := A_Temp "\fischxr_rod.txt"
    hbm := CaptureBitmap(r.x, r.y, r.w, r.h)
    big := 0, bmp := 0
    if Gdip.Start() {
        DllCall("gdiplus\GdipCreateBitmapFromHBITMAP", "Ptr", hbm, "Ptr", 0, "Ptr*", &bmp)
        big := GpScaled(bmp, r.w * 3, r.h * 3, 0)          ; bigger text reads better
        DllCall("gdiplus\GdipDisposeImage", "Ptr", bmp)
    }
    ok := SavePng(big ? big : hbm, png)
    DllCall("DeleteObject", "Ptr", hbm)
    if big
        DllCall("DeleteObject", "Ptr", big)
    if !ok
        return RodNameDone("", "couldn't capture the hotbar")
    RodReadAt := A_TickCount
    if IsObject(OcrHook)                                     ; tests
        return RodNameDone(OcrHook.Call(png), "")
    try FileDelete(out)
    ps := OcrScript()
    try {
        Run('powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "' ps '" "' png '" "' out '"', , "Hide")
    } catch {
        return RodNameDone("", "Windows' text reader isn't available")
    }
    RodReadBusy := true
    SetTimer(RodNamePoll, 200)
}

RodNamePoll() {
    global RodReadBusy
    if FileExist(A_Temp "\fischxr_rod.txt") {
        Sleep 60
        txt := ""
        try txt := FileRead(A_Temp "\fischxr_rod.txt", "UTF-8")
        SetTimer(RodNamePoll, 0), RodReadBusy := false
        return RodNameDone(txt, "")
    }
    if (A_TickCount - RodReadAt > 15000) {
        SetTimer(RodNamePoll, 0), RodReadBusy := false
        RodNameDone("", "the text reader didn't answer")
    }
}

RodNameDone(text, problem) {
    global CurRodName, CurRodLib, RodReadLast, RodReadBusy
    RodReadBusy := false
    name := problem = "" ? ParseRodName(text) : ""
    RodReadLast := problem != "" ? "Couldn't read the rod: " problem "." : name = "" ? "Couldn't read a rod name in the rod's hotbar slot." : ""
    if (name != "" && name != CurRodName) {
        CurRodName := name, CurRodLib := RodLibFor(name)
        LogEvent("Rod: " name)
    } else if (name = "") {
        CurRodName := "", CurRodLib := ""
    }
    try RodsChanged()
    try Hud.Update()
}

; The PowerShell script that runs Windows' text reader on an image.
OcrScript() {
    path := A_Temp "\fischxr_ocr.ps1"
    if FileExist(path)
        return path
    FileAppend("
(
param([string]$img, [string]$out)
$ErrorActionPreference = 'Stop'
try {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $null = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
    $null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
    $null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics, ContentType = WindowsRuntime]
    $asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation``1' })[0]
    function Await($op, $type) { $t = $asTask.MakeGenericMethod($type).Invoke($null, @($op)); $t.Wait(-1) | Out-Null; $t.Result }
    $file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($img)) ([Windows.Storage.StorageFile])
    $stream = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
    $decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
    $bitmap = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
    $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
    $result = Await ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
    ($result.Lines | ForEach-Object { $_.Text }) -join [Environment]::NewLine | Set-Content -Path $out -Encoding UTF8
} catch {
    '' | Set-Content -Path $out -Encoding UTF8
}
)", path, "UTF-8")
    return path
}


;==============================================================================
; Embedded images: the loading-screen logo and the app icon tile (PNG, base64).
; Kept in a function so they exist from the moment the script loads.
;==============================================================================
LogoData(which) {
    if (which = "splash")
        return "
(Join
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
)"
    return "
(Join
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
)"
}

