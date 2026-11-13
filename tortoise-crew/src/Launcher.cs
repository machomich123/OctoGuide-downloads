using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace TortoiseCrew
{
    internal static class Program
    {
        [STAThread]
        private static void Main(string[] args)
        {
            try
            {
                Directory.CreateDirectory(Paths.Root);
                if (args.Length == 4 && args[0] == "--watch")
                {
                    SessionMonitor.Watch(int.Parse(args[1]), int.Parse(args[2]), args[3]);
                    return;
                }
                if (args.Length == 3 && args[0] == "--replace")
                {
                    SafeUpdater.ReplaceInstalled(args[1], args[2]);
                    return;
                }
                if (args.Length == 2 && args[0] == "--replace")
                {
                    // Backwards-compatible update from v1.0.0/v1.0.1:
                    // they invoke downloaded EXEs with no SHA argument, having
                    // already validated the download against the GitHub manifest.
                    // Validate the currently published manifest again here.
                    var manifest = RemoteUpdates.Fetch();
                    string hash = GameDetector.HashOf(Assembly.GetExecutingAssembly().Location);
                    if (!String.Equals(manifest.LauncherSha256, hash, StringComparison.OrdinalIgnoreCase))
                        throw new InvalidDataException("The downloaded update is not in the trusted GitHub manifest.");
                    SafeUpdater.ReplaceInstalled(args[1], hash);
                    return;
                }

                string current = Path.GetFullPath(Assembly.GetExecutingAssembly().Location);
                if (!String.Equals(current, Paths.Executable, StringComparison.OrdinalIgnoreCase))
                {
                    bool shouldCopy = true;
                    if (File.Exists(Paths.Executable))
                    {
                        try
                        {
                            var oldVersion = AssemblyName.GetAssemblyName(Paths.Executable).Version;
                            var incoming = Assembly.GetExecutingAssembly().GetName().Version;
                            shouldCopy = oldVersion == null || oldVersion <= incoming;
                        }
                        catch { }
                    }
                    if (shouldCopy) File.Copy(current, Paths.Executable, true);
                    DesktopShortcut.Create();
                    Process.Start(new ProcessStartInfo(Paths.Executable) { WorkingDirectory = Paths.Root });
                    return;
                }

                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                Application.Run(new LauncherForm());
            }
            catch (Exception ex)
            {
                Paths.WriteLog("Startup: " + ex);
                MessageBox.Show(ex.Message, "Tortoise Crew Launcher",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }
    }

    internal static class DesktopShortcut
    {
        public static void Create()
        {
            try
            {
                string dir = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
                string link = Path.Combine(dir, "Tortoise Crew Launcher.lnk");
                Type shellType = Type.GetTypeFromProgID("WScript.Shell");
                if (shellType == null) return;
                dynamic shell = Activator.CreateInstance(shellType);
                dynamic shortcut = shell.CreateShortcut(link);
                shortcut.TargetPath = Paths.Executable;
                shortcut.WorkingDirectory = Paths.Root;
                shortcut.Description = "Tortoise Crew - Private WoW 1.18.1";
                shortcut.IconLocation = Paths.Executable + ",0";
                shortcut.Save();
            }
            catch (Exception ex) { Paths.WriteLog("Shortcut: " + ex.GetType().Name); }
        }
    }

    public sealed class LauncherForm : Form
    {
        private readonly Color background = Color.FromArgb(12, 18, 28);
        private readonly Color surface = Color.FromArgb(20, 30, 43);
        private readonly Color muted = Color.FromArgb(144, 160, 180);
        private readonly Color white = Color.FromArgb(240, 246, 251);
        private readonly Color accent = Color.FromArgb(98, 232, 190);
        private LauncherSettings settings;
        private RealmManifest currentManifest;
        private Label status, statusDescription, gamePath, information, feedMessage, versionLabel;
        private ComboBox username;
        private Button playButton, updateButton, browseButton, keyButton, settingsButton;
        private CheckBox loginToggle;
        private Process activeSsh, activeWow;
        private bool starting, checking, searching, updating, handedOffSession, closingForUpdate;

        public LauncherForm()
        {
            settings = Paths.Load();
            Text = "Tortoise Crew · Realm Launcher";
            ClientSize = new Size(1000, 650);
            MinimumSize = MaximumSize = Size;
            StartPosition = FormStartPosition.CenterScreen;
            BackColor = background;
            ForeColor = white;
            FormBorderStyle = FormBorderStyle.FixedSingle;
            MaximizeBox = false;
            Font = new Font("Segoe UI", 10f, FontStyle.Regular);
            DoubleBuffered = true;
            Icon = SystemIcons.Application;
            BuildLayout();
            FormClosing += OnClosing;
            Shown += async (s, e) =>
            {
                await InitializeAsync();
            };
        }

        private Label TextLabel(string text, int x, int y, int w, int h,
                                float size, Color color, FontStyle style = FontStyle.Regular)
        {
            var label = new Label
            {
                Text = text, Location = new Point(x, y), Size = new Size(w, h),
                Font = new Font("Segoe UI", size, style), ForeColor = color,
                BackColor = Color.Transparent, AutoEllipsis = true
            };
            Controls.Add(label);
            return label;
        }

        private Button MakeButton(string text, int x, int y, int w, int h, bool primary)
        {
            var b = new Button
            {
                Text = text, Location = new Point(x, y), Size = new Size(w, h),
                FlatStyle = FlatStyle.Flat, Cursor = Cursors.Hand,
                BackColor = primary ? accent : Color.FromArgb(38, 54, 71),
                ForeColor = primary ? Color.FromArgb(10, 32, 34) : white,
                Font = new Font("Segoe UI Semibold", primary ? 13f : 10f, FontStyle.Bold),
                UseVisualStyleBackColor = false
            };
            b.FlatAppearance.BorderSize = 0;
            b.FlatAppearance.MouseOverBackColor = primary
                ? Color.FromArgb(143, 246, 213) : Color.FromArgb(54, 73, 94);
            Controls.Add(b);
            b.Resize += (s, e) => RoundControl(b, 12);
            RoundControl(b, 12);
            return b;
        }

        private void RoundControl(Control c, int radius)
        {
            var rect = new Rectangle(0, 0, c.Width, c.Height);
            using (var path = RoundedRect(rect, radius))
            {
                var previous = c.Region;
                c.Region = new Region(path);
                if (previous != null) previous.Dispose();
            }
        }

        private static GraphicsPath RoundedRect(Rectangle r, int radius)
        {
            int size = radius * 2;
            var p = new GraphicsPath();
            p.AddArc(r.X, r.Y, size, size, 180, 90);
            p.AddArc(r.Right - size, r.Y, size, size, 270, 90);
            p.AddArc(r.Right - size, r.Bottom - size, size, size, 0, 90);
            p.AddArc(r.X, r.Bottom - size, size, size, 90, 90);
            p.CloseFigure();
            return p;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using (var bg = new LinearGradientBrush(ClientRectangle, background,
                         Color.FromArgb(16, 27, 42), LinearGradientMode.ForwardDiagonal))
                e.Graphics.FillRectangle(bg, ClientRectangle);
            using (var side = new SolidBrush(Color.FromArgb(16, 25, 38)))
                e.Graphics.FillRectangle(side, 0, 0, 232, Height);
            using (var rule = new SolidBrush(Color.FromArgb(45, 66, 80)))
                e.Graphics.FillRectangle(rule, 232, 0, 1, Height);

            using (var logo = new SolidBrush(accent))
                e.Graphics.FillEllipse(logo, 32, 30, 40, 40);
            using (var logoText = new SolidBrush(Color.FromArgb(14, 46, 45)))
            using (var f = new Font("Segoe UI", 14f, FontStyle.Bold))
                e.Graphics.DrawString("TC", f, logoText, 33, 37);

            using (var card = new SolidBrush(surface))
            {
                using (var p = RoundedRect(new Rectangle(263, 112, 699, 129), 18))
                    e.Graphics.FillPath(card, p);
                using (var p = RoundedRect(new Rectangle(263, 269, 699, 291), 18))
                    e.Graphics.FillPath(card, p);
            }
            using (var line = new Pen(Color.FromArgb(45, 65, 84)))
            {
                e.Graphics.DrawLine(line, 289, 375, 936, 375);
                e.Graphics.DrawLine(line, 289, 467, 936, 467);
            }
        }

        private void BuildLayout()
        {
            TextLabel("TORTOISE", 82, 32, 139, 23, 15, white, FontStyle.Bold);
            TextLabel("CREW", 82, 57, 138, 19, 10, accent, FontStyle.Bold);
            TextLabel("PRIVATE REALM", 30, 132, 190, 20, 9, muted, FontStyle.Bold);
            TextLabel("MYSTERIES OF AZEROTH", 30, 160, 200, 23, 10, white);
            TextLabel("1.18.1  ·  BUILD 7272", 30, 194, 196, 18, 8.5f, muted);
            TextLabel("CREW", 30, 285, 180, 18, 9, muted, FontStyle.Bold);
            TextLabel("MICHAEL", 33, 316, 167, 24, 11, white);
            TextLabel("JAYKE", 33, 344, 167, 24, 11, white);
            TextLabel("BERNARD", 33, 372, 167, 24, 11, white);
            TextLabel("AUGUST", 33, 400, 167, 24, 11, white);
            TextLabel("One launcher. One realm.", 28, 584, 192, 22, 9, muted);
            versionLabel = TextLabel("Launcher v" + Paths.Version, 28, 611, 193, 20, 9, muted);

            TextLabel("Welcome back, adventurer.", 265, 31, 680, 41, 21.5f, white, FontStyle.Bold);
            TextLabel("Your private Tortoise realm", 266, 79, 660, 24, 11, muted);

            TextLabel("SERVER STATUS", 289, 133, 210, 25, 9.5f, muted, FontStyle.Bold);
            status = TextLabel("Checking connection...", 289, 160, 560, 33, 17, white, FontStyle.Bold);
            statusDescription = TextLabel("Checking the Altare node and game world.", 289, 204, 640, 22, 9.5f, muted);

            TextLabel("YOUR ACCOUNT", 290, 290, 260, 22, 9.5f, muted, FontStyle.Bold);
            username = new ComboBox
            {
                Location = new Point(290, 319), Size = new Size(296, 32),
                DropDownStyle = ComboBoxStyle.DropDown, FlatStyle = FlatStyle.Flat,
                BackColor = Color.FromArgb(36, 51, 69), ForeColor = white,
                Font = new Font("Segoe UI", 12f)
            };
            username.Items.AddRange(new object[] { "MICHAEL", "JAYKE", "BERNARD", "AUGUST" });
            username.Text = settings.Username;
            username.TextChanged += (s, e) => SaveUsername();
            Controls.Add(username);

            loginToggle = new CheckBox
            {
                Text = "Auto-login using shared password (1)",
                Location = new Point(603, 327), Size = new Size(333, 27),
                Checked = settings.AutoLogin, ForeColor = white, BackColor = surface,
                Font = new Font("Segoe UI", 9f)
            };
            loginToggle.CheckedChanged += (s, e) =>
            {
                settings.AutoLogin = loginToggle.Checked;
                Paths.Save(settings);
            };
            Controls.Add(loginToggle);

            TextLabel("VERIFIED WOW CLIENT", 291, 395, 250, 19, 9.5f, muted, FontStyle.Bold);
            gamePath = TextLabel("Looking for WoW 1.18.1...", 290, 425, 484, 25, 10, white);
            browseButton = MakeButton("Change file", 813, 413, 121, 38, false);
            browseButton.Click += (s, e) => BrowseGame();

            information = TextLabel("First time? A unique SSH key is created for this PC.",
                289, 486, 632, 27, 10, muted);

            playButton = MakeButton("▶   PLAY TORTOISE WOW", 266, 585, 365, 53, true);
            playButton.Click += async (s, e) => await PlayAsync();
            updateButton = MakeButton("↻  Update", 650, 585, 153, 53, false);
            updateButton.Click += async (s, e) => await UpdateAsync(true);
            settingsButton = MakeButton("Settings", 814, 585, 149, 53, false);
            settingsButton.Click += (s, e) => ShowSettings();

            feedMessage = TextLabel("Updates are checked on GitHub. No passwords are sent.",
                267, 548, 680, 22, 9, muted);
        }

        private void SaveUsername()
        {
            string chosen = (username.Text ?? "").Trim().ToUpperInvariant();
            if (chosen.Length == 0 || chosen.Length > 24) return;
            settings.Username = chosen;
            Paths.Save(settings);
        }

        private async Task InitializeAsync()
        {
            try
            {
                SshSupport.ExistingOrNewKey(settings);
            }
            catch (Exception ex)
            {
                Notice("OpenSSH is not ready: " + ex.Message);
            }

            if (!GameDetector.IsVerified(settings.WowPath))
            {
                searching = true;
                gamePath.Text = "Searching for the correct WoW.exe...";
                try
                {
                    string found = await Task.Run(() => GameDetector.Find((count, folder) =>
                    {
                        if (!IsDisposed && IsHandleCreated)
                            BeginInvoke((Action)(() => gamePath.Text = "Scanned " + count + " folders..."));
                    }));
                    if (!String.IsNullOrEmpty(found))
                    {
                        settings.WowPath = found;
                        Paths.Save(settings);
                        Notice("The correct WoW.exe was found and verified.");
                    }
                    else
                    {
                        Notice("Verified WoW.exe was not found. Use Change file.");
                        BrowseGame();
                    }
                }
                catch (Exception ex)
                {
                    Paths.WriteLog("Game scan: " + ex);
                    Notice("Search finished. Choose WoW.exe manually.");
                }
                finally { searching = false; }
            }
            UpdateGameLabel();
            await UpdateAsync(false);
            await CheckStatusAsync();
        }

        private void UpdateGameLabel()
        {
            if (GameDetector.IsVerified(settings.WowPath))
                gamePath.Text = "✓  " + settings.WowPath;
            else
                gamePath.Text = "Verified WoW.exe missing (1.18.1 / 7272)";
        }

        private void BrowseGame()
        {
            var selected = GameDetector.Browse(settings.WowPath);
            if (String.IsNullOrEmpty(selected)) return;
            settings.WowPath = selected;
            Paths.Save(settings);
            UpdateGameLabel();
            Notice("Verified game client: " + Path.GetDirectoryName(selected));
        }

        private void Notice(string message)
        {
            information.Text = message;
            Paths.WriteLog(message);
        }

        private async Task CheckStatusAsync()
        {
            if (checking) return;
            checking = true;
            status.Text = "Checking server status...";
            status.ForeColor = white;
            try
            {
                bool reachable = await Task.Run(() => SshSupport.PortOpen(settings.Host, settings.SshPort, 5000));
                if (!reachable)
                {
                    status.Text = "Server unavailable";
                    status.ForeColor = Color.FromArgb(247, 147, 138);
                    statusDescription.Text = settings.Host + ":" + settings.SshPort + " is not responding.";
                    return;
                }

                bool world = await SshSupport.ProbeGameAsync(settings);
                status.Text = world ? "Realm online  ●" : "Altare online  ◉";
                status.ForeColor = world ? accent : Color.FromArgb(254, 205, 129);
                statusDescription.Text = world
                    ? "The game world responded to an authenticated check."
                    : "SSH is reachable. Your key may need approval, or the game is offline.";
            }
            catch (Exception ex)
            {
                status.Text = "Status unavailable";
                status.ForeColor = Color.FromArgb(254, 205, 129);
                Paths.WriteLog("Status: " + ex);
            }
            finally { checking = false; }
        }

        private async Task UpdateAsync(bool userRequested)
        {
            if (updating) return;
            updating = true;
            updateButton.Enabled = false;
            updateButton.Text = "Checking...";
            try
            {
                RealmManifest manifest = await Task.Run(() => RemoteUpdates.Fetch());
                currentManifest = manifest;
                bool routingChanged = settings.Host != manifest.Host ||
                                      settings.SshPort != manifest.SshPort ||
                                      settings.AuthPort != manifest.AuthPort ||
                                      settings.WorldPort != manifest.WorldPort;
                if (routingChanged)
                {
                    RemoteUpdates.ApplyRouting(settings, manifest);
                    Notice("Server connection settings were updated from GitHub.");
                }

                if (RemoteUpdates.IsNewer(manifest))
                {
                    updateButton.Text = "Update v" + manifest.LauncherVersion;
                    feedMessage.Text = "New version available: " + manifest.LauncherVersion;
                    if (userRequested)
                    {
                        var ask = MessageBox.Show(
                            "Version " + manifest.LauncherVersion + " is ready.\n\nInstall it now?",
                            "Launcher update", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
                        if (ask == DialogResult.Yes)
                        {
                            if (SessionMonitor.IsSessionActive() || activeWow != null)
                            {
                                Notice("Close WoW before installing a launcher update.");
                                return;
                            }
                            updateButton.Text = "DOWNLOADING...";
                            feedMessage.Text = "Downloading and verifying the signed-off update...";
                            string candidate = await RemoteUpdates.DownloadVerifiedUpdateAsync(manifest);
                            if (!File.Exists(candidate))
                                throw new IOException("Update download was not saved.");
                            Paths.WriteLog("SHA-256 verified. Starting safe, independent updater.");
                            var helperStart = new ProcessStartInfo(candidate,
                                "--replace \"" + Paths.Executable + "\" " + manifest.LauncherSha256)
                            {
                                WorkingDirectory = Paths.Root,
                                UseShellExecute = false,
                                CreateNoWindow = true,
                                WindowStyle = ProcessWindowStyle.Hidden
                            };
                            using (var helper = Process.Start(helperStart))
                            {
                                if (helper == null) throw new IOException("Could not start update helper.");
                            }
                            closingForUpdate = true;
                            Hide();
                            Close();
                            return;
                        }
                    }
                }
                else
                {
                    updateButton.Text = "↻  Update";
                    feedMessage.Text = routingChanged ? "Server settings updated from GitHub." :
                        "Launcher and server settings are up to date.";
                    if (userRequested) Notice("You are using the latest launcher.");
                }
            }
            catch (Exception ex)
            {
                updateButton.Text = "↻  Update";
                feedMessage.Text = "GitHub is unavailable. Using saved server settings.";
                Paths.WriteLog("Manifest fetch: " + ex.GetType().Name + ": " + ex.Message);
                if (userRequested) Notice("Couldn't check updates. Please try again.");
            }
            finally
            {
                updating = false;
                if (!IsDisposed && !Disposing && !closingForUpdate)
                    updateButton.Enabled = true;
            }
        }

        private async Task PlayAsync()
        {
            if (starting || searching) return;
            string account = (username.Text ?? "").Trim().ToUpperInvariant();
            if (!System.Text.RegularExpressions.Regex.IsMatch(account, "^[A-Z0-9]{2,24}$"))
            {
                MessageBox.Show("Choose MICHAEL, JAYKE, BERNARD, or AUGUST first.",
                    "Account", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }
            settings.Username = account;
            Paths.Save(settings);
            if (!GameDetector.IsVerified(settings.WowPath))
            {
                BrowseGame();
                if (!GameDetector.IsVerified(settings.WowPath)) return;
            }
            if (SshSupport.PortOpen("127.0.0.1", 3724, 200) ||
                SshSupport.PortOpen("127.0.0.1", 8085, 200))
            {
                MessageBox.Show("Port 3724 or 8085 is already used by another WoW tunnel.\n" +
                    "Close the other connection first.", "Connection in use",
                    MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }
            starting = true;
            playButton.Enabled = false;
            playButton.Text = "CONNECTING...";
            try
            {
                SshSupport.ExistingOrNewKey(settings);
                GameDetector.Configure(settings.WowPath, account);
                activeSsh = SshSupport.StartTunnel(settings);

                bool ready = await Task.Run(() =>
                {
                    for (int i = 0; i < 40; i++)
                    {
                        if (activeSsh == null || activeSsh.HasExited) return false;
                        if (SshSupport.PortOpen("127.0.0.1", 3724, 400) &&
                            SshSupport.WorldChallenge()) return true;
                        Thread.Sleep(500);
                    }
                    return false;
                });
                if (!ready)
                {
                    string error = "";
                    try
                    {
                        if (activeSsh != null && activeSsh.HasExited)
                            error = activeSsh.StandardError.ReadToEnd();
                    }
                    catch { }
                    Paths.WriteLog("SSH tunnel failed: " + error);
                    if (error.IndexOf("Permission denied", StringComparison.OrdinalIgnoreCase) >= 0 ||
                        error.IndexOf("publickey", StringComparison.OrdinalIgnoreCase) >= 0)
                    {
                        ShowPublicKey(true);
                        Notice("This PC's public SSH key must be approved once by Michael.");
                    }
                    else
                    {
                        MessageBox.Show("Could not open the game connection.\n\n" +
                            (String.IsNullOrEmpty(error) ? "Check server status and that this SSH key has been approved." :
                              error.Substring(0, Math.Min(700, error.Length))),
                            "Connection error", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    }
                    return;
                }

                var gameStart = new ProcessStartInfo(settings.WowPath)
                {
                    WorkingDirectory = Path.GetDirectoryName(settings.WowPath),
                    UseShellExecute = true
                };
                activeWow = Process.Start(gameStart);
                if (activeWow == null) throw new InvalidOperationException("WoW.exe could not be started.");
                Notice("WoW launched. The private tunnel stays connected while you play.");
                playButton.Text = "GAME RUNNING...";
                if (settings.AutoLogin)
                    await AutoLogin.TryLoginAsync(activeWow, account);
                if (!await SessionMonitor.HandOffAsync(activeWow.Id, activeSsh.Id))
                    throw new InvalidOperationException(
                        "The background game-session monitor could not start; the launcher will keep the tunnel until you retry.");
                handedOffSession = true;
                Paths.WriteLog("WoW launched successfully. Closing UI; background session monitor owns SSH.");
                Close();
                return;
            }
            catch (Exception ex)
            {
                Paths.WriteLog("Play failed: " + ex);
                MessageBox.Show(ex.Message + "\n\nLog: " + Paths.Log, "Launch failed",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
            finally
            {
                // After confirmed handoff, the background monitor must keep SSH alive.
                if (!handedOffSession)
                {
                    try { if (activeSsh != null && !activeSsh.HasExited) activeSsh.Kill(); } catch { }
                }
                try { if (activeSsh != null) activeSsh.Dispose(); } catch { }
                try { if (activeWow != null) activeWow.Dispose(); } catch { }
                activeSsh = null;
                activeWow = null;
                starting = false;
                if (!IsDisposed && !Disposing && !handedOffSession)
                {
                    playButton.Enabled = true;
                    playButton.Text = "▶   PLAY TORTOISE WOW";
                    await CheckStatusAsync();
                }
            }
        }

        private void ShowPublicKey(bool showInstructions)
        {
            try
            {
                string publicKey = SshSupport.PublicKey(settings);
                Clipboard.SetText(publicKey);
                MessageBox.Show(
                    "Your public SSH key has been copied to the clipboard.\n\n" +
                    "Send it to Michael for one-time approval on the Altare server.\n" +
                    "Never share your PRIVATE key.\n\n" +
                    (showInstructions ? "This computer needs SSH access. " : "") +
                    "Once approved, press Play. No other setup is needed.",
                    "First-time setup", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            catch (Exception ex) { MessageBox.Show(ex.Message, "SSH key"); }
        }

        private void ShowSettings()
        {
            using (var dialog = new Form())
            {
                dialog.Text = "Tortoise Crew - Settings";
                dialog.ClientSize = new Size(610, 330);
                dialog.StartPosition = FormStartPosition.CenterParent;
                dialog.FormBorderStyle = FormBorderStyle.FixedDialog;
                dialog.MaximizeBox = false;
                dialog.MinimizeBox = false;
                dialog.BackColor = background;
                dialog.ForeColor = white;
                dialog.Font = Font;
                var header = new Label { Text = "CONNECTION", Location = new Point(20, 18),
                    Size = new Size(430, 30), Font = new Font("Segoe UI", 16, FontStyle.Bold),
                    ForeColor = accent };
                dialog.Controls.Add(header);
                var endpoint = new Label
                {
                    Text = settings.Host + ":" + settings.SshPort + "   →   127.0.0.1:3724 / 8085",
                    Location = new Point(23, 61), Size = new Size(554, 31), ForeColor = muted
                };
                dialog.Controls.Add(endpoint);

                var pathLabel = new Label { Text = "Selected WoW.exe:", Location = new Point(22, 112),
                    Size = new Size(170, 25) };
                dialog.Controls.Add(pathLabel);
                var pathText = new TextBox { Text = settings.WowPath, Location = new Point(22, 143),
                    Size = new Size(557, 25), ReadOnly = true };
                dialog.Controls.Add(pathText);

                var choose = new Button { Text = "Choose WoW.exe", Location = new Point(22, 186),
                    Size = new Size(151, 34) };
                choose.Click += (s, e) =>
                {
                    BrowseGame();
                    pathText.Text = settings.WowPath;
                };
                dialog.Controls.Add(choose);

                var copy = new Button { Text = "Copy public SSH key",
                    Location = new Point(188, 186), Size = new Size(225, 34) };
                copy.Click += (s, e) => ShowPublicKey(false);
                dialog.Controls.Add(copy);

                var folder = new Button { Text = "View logs",
                    Location = new Point(428, 186), Size = new Size(151, 34) };
                folder.Click += (s, e) =>
                {
                    Directory.CreateDirectory(Paths.Root);
                    Process.Start("explorer.exe", Paths.Root);
                };
                dialog.Controls.Add(folder);

                var help = new Label { Text = "Game server ports are updated automatically from GitHub. " +
                        "On a new PC, send your public SSH key to Michael for approval.",
                    Location = new Point(22, 251), Size = new Size(550, 51), ForeColor = muted };
                dialog.Controls.Add(help);
                dialog.ShowDialog(this);
            }
        }

        private void OnClosing(object sender, FormClosingEventArgs e)
        {
            if (handedOffSession || closingForUpdate)
                return;
            // Never kill the tunnel if closing was cancelled.
            if (activeWow != null)
            {
                try
                {
                    if (!activeWow.HasExited)
                    {
                        MessageBox.Show("WoW is still running. The launcher must remain open until " +
                                        "the background session monitor is ready.",
                            "Tortoise Crew", MessageBoxButtons.OK, MessageBoxIcon.Information);
                        e.Cancel = true;
                        return;
                    }
                }
                catch { }
            }
            try { if (activeSsh != null && !activeSsh.HasExited) activeSsh.Kill(); }
            catch { }
        }
    }
}
