using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Net;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace TortoiseCrew
{
    // In-launcher Addons page. It overlays the main content while leaving the crew sidebar visible.
    public sealed class AddonHub : UserControl
    {
        private static readonly Color Bg = Color.FromArgb(12, 18, 28);
        private static readonly Color Card = Color.FromArgb(24, 36, 50);
        private static readonly Color TextColor = Color.FromArgb(235, 244, 251);
        private static readonly Color Muted = Color.FromArgb(157, 176, 193);
        private static readonly Color Mint = Color.FromArgb(98, 232, 190);
        private readonly Func<string> wowPath;
        private readonly Action<string> notify;
        private readonly FlowLayoutPanel gallery;
        private readonly TextBox search;
        private readonly ComboBox provider;
        private readonly Label feedback;
        private readonly Button scan;
        private List<AddonEntry> addons = new List<AddonEntry>();
        private string page = "Browse";
        private int offset;
        private bool working;
        private readonly Button previous, next;
        private readonly Label pageNumber, perPageLabel;
        private readonly ComboBox sortControl;
        private readonly NumericUpDown resultsPerPage;

        public AddonHub(Func<string> getPath, Action<string> report)
        {
            wowPath = getPath;
            notify = report;
            Location = new Point(233, 0);
            Size = new Size(767, 650);
            BackColor = Bg;
            Font = new Font("Segoe UI", 9.5f);
            var title = Label("ADDON LIBRARY", 26, 23, 510, 38, 22, TextColor, true);
            Label("Browse, install and migrate addons for your 1.18.1 client", 27, 65, 660, 24, 10, Muted);

            Button tabBrowse = Button("Discover", 26, 108, 111, 34, true);
            Button tabInstalled = Button("Installed", 145, 108, 104, 34);
            Button tabPacks = Button("Packs & DLLs", 257, 108, 132, 34);
            Button sitesButton = Button("Addon sites", 609, 108, 130, 34);
            sitesButton.Click += (s, e) => ShowSites();
            tabBrowse.Click += (s, e) => { page = "Browse"; Render(); };
            tabInstalled.Click += (s, e) => { page = "Installed"; Render(); };
            tabPacks.Click += (s, e) => { page = "Packs"; Render(); };

            search = new TextBox
            {
                Location = new Point(27, 155), Size = new Size(365, 29),
                BackColor = Color.FromArgb(34, 49, 67), ForeColor = TextColor,
                BorderStyle = BorderStyle.FixedSingle, Font = new Font("Segoe UI", 11)
            };
            search.TextChanged += (s, e) => { offset = 0; if (page != "Installed") Render(); };
            search.KeyDown += async (s, e) =>
            {
                if (e.KeyCode == Keys.Enter && provider.SelectedIndex == 1)
                {
                    e.SuppressKeyPress = true;
                    await SearchGithubAsync();
                }
            };
            Controls.Add(search);
            provider = new ComboBox
            {
                Location = new Point(404, 154), Size = new Size(175, 29),
                BackColor = Color.FromArgb(34, 49, 67), ForeColor = TextColor,
                DropDownStyle = ComboBoxStyle.DropDownList
            };
            provider.Items.AddRange(new object[] { "Turtle WoW catalog", "GitHub search" });
            provider.SelectedIndex = 0;
            provider.SelectedIndexChanged += async (s, e) =>
            {
                offset = 0;
                if (provider.SelectedIndex == 1 && page == "Browse")
                    await SearchGithubAsync();
                else Render();
            };
            Controls.Add(provider);
            scan = Button("Scan clients", 589, 154, 152, 31);
            scan.Click += async (s, e) => await ScanAsync();

            gallery = new FlowLayoutPanel
            {
                Location = new Point(24, 200), Size = new Size(721, 364),
                AutoScroll = true, WrapContents = false, FlowDirection = FlowDirection.TopDown,
                BackColor = Bg, Padding = new Padding(0)
            };
            Controls.Add(gallery);
            previous = Button("Previous", 27, 575, 107, 34);
            next = Button("Next", 628, 575, 107, 34);
            sortControl = new ComboBox
            {
                Location = new Point(145, 576), Size = new Size(226, 31),
                DropDownStyle = ComboBoxStyle.DropDownList,
                BackColor = Color.FromArgb(34, 49, 67), ForeColor = TextColor
            };
            sortControl.Items.AddRange(new object[] {
                "Popular (stars)", "Downloads (if known)", "Recently updated",
                "Name A-Z", "Name Z-A", "Stars: lowest first"
            });
            sortControl.SelectedIndex = 0;
            sortControl.SelectedIndexChanged += (s, e) => { offset = 0; Render(); };
            Controls.Add(sortControl);
            resultsPerPage = new NumericUpDown
            {
                Location = new Point(383, 576), Size = new Size(70, 31),
                Minimum = 6, Maximum = 500, Increment = 12, Value = 24,
                BackColor = Color.FromArgb(34, 49, 67), ForeColor = TextColor
            };
            resultsPerPage.ValueChanged += (s, e) => { offset = 0; Render(); };
            Controls.Add(resultsPerPage);
            perPageLabel = Label("per page", 455, 583, 73, 22, 8, Muted);
            pageNumber = Label("", 532, 583, 96, 22, 8, Muted);
            pageNumber.TextAlign = ContentAlignment.MiddleRight;
            previous.Click += (s, e) => { offset = Math.Max(0, offset - (int)resultsPerPage.Value); Render(); };
            next.Click += (s, e) => { offset += (int)resultsPerPage.Value; Render(); };

            feedback = Label("Loading the Turtle WoW addon catalog...", 27, 621, 710, 22, 9, Muted);
            ShownLoad();
        }

        private Label Label(string text, int x, int y, int w, int h, float size, Color color, bool bold = false)
        {
            var l = new Label
            {
                Text = text, Location = new Point(x, y), Size = new Size(w, h),
                Font = new Font("Segoe UI", size, bold ? FontStyle.Bold : FontStyle.Regular),
                ForeColor = color, BackColor = Color.Transparent, AutoEllipsis = true
            };
            Controls.Add(l);
            return l;
        }
        private Button Button(string text, int x, int y, int w, int h, bool highlighted = false)
        {
            var b = new Button
            {
                Text = text, Location = new Point(x, y), Size = new Size(w, h),
                BackColor = highlighted ? Mint : Color.FromArgb(40, 56, 73),
                ForeColor = highlighted ? Color.FromArgb(13, 39, 38) : TextColor,
                FlatStyle = FlatStyle.Flat, Cursor = Cursors.Hand,
                Font = new Font("Segoe UI", 9, FontStyle.Bold)
            };
            b.FlatAppearance.BorderSize = 0;
            Controls.Add(b);
            return b;
        }
        private void Say(string message)
        {
            feedback.Text = message;
            if (notify != null) notify(message);
        }
        private async void ShownLoad()
        {
            try
            {
                addons = await AddonCatalog.LoadAsync();
                if (!IsDisposed) { Say("Catalog ready: " + addons.Count + " community addons."); Render(); }
            }
            catch (Exception ex)
            {
                if (!IsDisposed) Say("Could not load catalog: " + ex.Message);
            }
        }
        private async Task SearchGithubAsync()
        {
            if (working) return;
            if (String.IsNullOrWhiteSpace(search.Text))
            {
                Say("Type an addon name before searching GitHub.");
                return;
            }
            working = true;
            Say("Searching public GitHub repositories...");
            try
            {
                var results = await AddonCatalog.SearchGithubAsync(search.Text);
                if (IsDisposed) return;
                githubResults = results;
                Say("GitHub returned " + results.Count + " repositories. Check game compatibility before installing.");
                Render();
            }
            catch (Exception ex) { if (!IsDisposed) Say("GitHub search: " + ex.Message); }
            finally { working = false; }
        }
        private List<AddonEntry> githubResults = new List<AddonEntry>();
        private void ShowSites()
        {
            var sites = new Dictionary<string, string>
            {
                { "Turtle WoW addon wiki (our catalog)", "https://turtle-wow.fandom.com/wiki/Addons" },
                { "GitHub · Turtle WoW addons", "https://github.com/topics/turtle-wow-addon" },
                { "OctoWoW modding forum", "https://octowow.st/forum/viewforum.php?f=9" },
                { "Legacy WoW · Vanilla addons", "https://legacy-wow.com/vanilla-addons/" },
                { "CurseForge · WoW addons (version differs)", "https://www.curseforge.com/wow/addons" }
            };
            using (var d = new Form { Text = "Addon source websites", Size = new Size(630, 380),
                StartPosition = FormStartPosition.CenterParent, BackColor = Bg, ForeColor = TextColor })
            {
                var note = new Label { Text = "The catalog installs compatible GitHub addon ZIPs directly. Other sites open in your browser; many downloads target newer WoW versions.",
                    Location = new Point(18, 15), Size = new Size(580, 54), ForeColor = Muted };
                d.Controls.Add(note);
                int y = 77;
                foreach (var site in sites)
                {
                    var button = new Button { Text = site.Key, Location = new Point(18, y), Size = new Size(575, 40),
                        FlatStyle = FlatStyle.Flat, ForeColor = TextColor, BackColor = Card };
                    string url = site.Value;
                    button.Click += (s, e) => Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
                    d.Controls.Add(button);
                    y += 46;
                }
                d.ShowDialog(FindForm());
            }
        }
        private void Render()
        {
            if (IsDisposed) return;
            gallery.SuspendLayout();
            gallery.Controls.Clear();
            search.Visible = page == "Browse";
            provider.Visible = page == "Browse";
            scan.Visible = page != "Browse";
            previous.Visible = next.Visible = page == "Browse";
            pageNumber.Visible = page == "Browse";
            sortControl.Visible = page == "Browse";
            resultsPerPage.Visible = page == "Browse";
            perPageLabel.Visible = page == "Browse";
            if (page == "Installed")
            {
                RenderInstalled();
            }
            else
            {
                var list = page == "Packs" ? AddonCatalog.Packs() :
                    (provider.SelectedIndex == 1 ? githubResults : addons);
                if (page == "Browse" && provider.SelectedIndex == 0 && !String.IsNullOrWhiteSpace(search.Text))
                    list = list.Where(a => (a.Name + " " + a.Description + " " + a.Author)
                        .IndexOf(search.Text, StringComparison.OrdinalIgnoreCase) >= 0).ToList();
                if (page == "Browse")
                {
                    switch (sortControl.SelectedIndex)
                    {
                        case 1: list = list.OrderByDescending(a => a.Downloads.HasValue)
                            .ThenByDescending(a => a.Downloads ?? -1).ThenByDescending(a => a.Stars).ToList(); break;
                        case 2: list = list.OrderByDescending(a => a.Updated)
                            .ThenByDescending(a => a.Stars).ToList(); break;
                        case 3: list = list.OrderBy(a => a.Name, StringComparer.OrdinalIgnoreCase).ToList(); break;
                        case 4: list = list.OrderByDescending(a => a.Name, StringComparer.OrdinalIgnoreCase).ToList(); break;
                        case 5: list = list.OrderBy(a => a.Stars).ThenBy(a => a.Name).ToList(); break;
                        default: list = list.OrderByDescending(a => a.Stars).ThenBy(a => a.Name).ToList(); break;
                    }
                }
                int total = list.Count;
                int size = (int)resultsPerPage.Value;
                offset = Math.Min(offset, Math.Max(0, ((total - 1) / size) * size));
                foreach (var item in list.Skip(offset).Take(page == "Packs" ? 40 : size))
                    AddCard(item);
                pageNumber.Text = total == 0 ? "No results" :
                    (offset + 1) + "–" + Math.Min(offset + size, total) + "/" + total;
                previous.Enabled = offset > 0;
                next.Enabled = offset + size < total;
            }
            gallery.ResumeLayout(true);
        }
        private static PictureBox Art(string uri, int x, int y, int w, int h)
        {
            var p = new PictureBox
            {
                Location = new Point(x, y), Size = new Size(w, h),
                BackColor = Color.FromArgb(54, 71, 91),
                SizeMode = PictureBoxSizeMode.Zoom
            };
            var bmp = new Bitmap(Math.Max(1, w), Math.Max(1, h));
            using (var g = Graphics.FromImage(bmp))
            {
                g.Clear(Color.FromArgb(43, 65, 81));
                using (var f = new Font("Segoe UI", 23, FontStyle.Bold))
                using (var brush = new SolidBrush(Mint))
                    g.DrawString("✦", f, brush, new PointF(w / 3f, h / 4f));
            }
            p.Image = bmp;
            if (!String.IsNullOrWhiteSpace(uri) && uri.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
            {
                // LoadAsync is non-blocking; a missing image leaves the placeholder.
                try { p.LoadAsync(uri); } catch { }
            }
            return p;
        }
        private void AddCard(AddonEntry entry)
        {
            var card = new Panel
            {
                Size = new Size(676, 103), Margin = new Padding(3, 2, 3, 7),
                BackColor = Card
            };
            card.Controls.Add(Art(entry.IconUrl, 13, 15, 71, 71));
            var name = new Label
            {
                Text = entry.Name, Location = new Point(97, 8), Size = new Size(355, 24),
                Font = new Font("Segoe UI", 11.5f, FontStyle.Bold), ForeColor = TextColor, AutoEllipsis = true
            };
            var desc = new Label
            {
                Text = entry.Description, Location = new Point(97, 34), Size = new Size(388, 43),
                Font = new Font("Segoe UI", 9f), ForeColor = Muted, AutoEllipsis = true
            };
            var meta = new Label
            {
                Text = entry.Source + "  ·  ★ " + entry.Stars +
                    (entry.Downloads.HasValue ? "  ·  ↓ " + entry.Downloads.Value.ToString("N0") : ""),
                Location = new Point(97, 82), Size = new Size(390, 17),
                Font = new Font("Segoe UI", 8), ForeColor = Mint, AutoEllipsis = true
            };
            card.Controls.Add(name);
            card.Controls.Add(desc);
            card.Controls.Add(meta);
            var details = SmallButton("Details", 538, 13, 116);
            details.Click += (s, e) =>
            {
                if (entry.IsPack)
                    MessageBox.Show(entry.Description + "\n\nUse Import to select a local installation or pack." + (String.IsNullOrEmpty(entry.Url) ? "" : "\nSource: " + entry.Url),
                        entry.Name, MessageBoxButtons.OK, MessageBoxIcon.Information);
                else
                    using (var view = new AddonDetails(entry, () => InstallAsync(entry)))
                        view.ShowDialog(FindForm());
            };
            var install = SmallButton(entry.IsPack ? "Import" : "Install", 538, 56, 116);
            install.Click += async (s, e) => await InstallAsync(entry);
            card.Controls.Add(details);
            card.Controls.Add(install);
            gallery.Controls.Add(card);
        }
        private Button SmallButton(string text, int x, int y, int width)
        {
            var b = new Button
            {
                Text = text, Location = new Point(x, y), Size = new Size(width, 33),
                BackColor = text == "Install" || text == "Import" ? Mint : Color.FromArgb(46, 66, 86),
                ForeColor = text == "Install" || text == "Import" ? Color.FromArgb(12, 37, 38) : TextColor,
                FlatStyle = FlatStyle.Flat, Font = new Font("Segoe UI", 9, FontStyle.Bold),
                Cursor = Cursors.Hand
            };
            b.FlatAppearance.BorderSize = 0;
            return b;
        }
        private void RenderInstalled()
        {
            try
            {
                var installed = AddonFiles.Installed(wowPath());
                if (installed.Count == 0)
                {
                    gallery.Controls.Add(new Label
                    {
                        Text = "No addons detected. Select Discover, or Scan clients to import existing addons.",
                        Size = new Size(650, 70), ForeColor = Muted, BackColor = Bg
                    });
                    return;
                }
                foreach (var item in installed)
                {
                    var c = new Panel { Size = new Size(676, 68), Margin = new Padding(3, 2, 3, 5), BackColor = Card };
                    c.Controls.Add(new Label
                    {
                        Text = item.Name, Location = new Point(15, 6), Size = new Size(625, 24),
                        ForeColor = TextColor, Font = new Font("Segoe UI", 11, FontStyle.Bold)
                    });
                    c.Controls.Add(new Label
                    {
                        Text = !String.IsNullOrEmpty(item.MissingDependencies) ? "Missing required addons: " + item.MissingDependencies :
                            (String.IsNullOrEmpty(item.Dependencies) ? "Installed · No declared dependencies" :
                            "Dependencies: " + item.Dependencies),
                        Location = new Point(15, 36), Size = new Size(635, 25),
                        ForeColor = Muted, AutoEllipsis = true
                    });
                    gallery.Controls.Add(c);
                }
                Say(installed.Count + " addons found in your active WoW installation.");
            }
            catch (Exception ex) { Say(ex.Message); }
        }
        private async Task InstallAsync(AddonEntry item)
        {
            if (working) return;
            if (item.IsPack)
            {
                await ImportViaPickerAsync(true);
                return;
            }
            if (Process.GetProcessesByName("WoW").Length > 0)
            {
                Say("Close WoW before installing addons.");
                return;
            }
            if (MessageBox.Show("Install " + item.Name + " from:\n" + item.Url +
                "\n\nOnly WoW addon folders containing .toc files are installed. Existing versions are backed up.",
                "Confirm addon install", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
            working = true;
            Say("Installing " + item.Name + "...");
            try
            {
                int count = await AddonFiles.DownloadAndInstallAsync(item, wowPath());
                if (IsDisposed) return;
                Say("Installed " + count + " addon folder(s) from " + item.Name + ". Restart WoW to load them.");
            }
            catch (Exception ex) { if (!IsDisposed) Say("Install failed: " + ex.Message); }
            finally { working = false; }
        }
        private async Task ScanAsync()
        {
            if (working) return;
            working = true;
            Say("Scanning drives for existing OctoWoW / Turtle WoW installations...");
            try
            {
                var clients = await AddonFiles.FindClientsAsync(wowPath());
                if (IsDisposed) return;
                if (clients.Count == 0)
                {
                    Say("No other installation detected. Select a folder manually.");
                    await ImportViaPickerAsync(true);
                    return;
                }
                using (var selection = new Form
                {
                    Text = "Import from existing WoW client", Size = new Size(700, 420),
                    StartPosition = FormStartPosition.CenterParent, BackColor = Bg, ForeColor = TextColor
                })
                {
                    var list = new ListBox
                    {
                        Location = new Point(15, 16), Size = new Size(653, 275),
                        BackColor = Card, ForeColor = TextColor, Font = new Font("Segoe UI", 10)
                    };
                    list.Items.AddRange(clients.Cast<object>().ToArray());
                    if (list.Items.Count > 0) list.SelectedIndex = 0;
                    selection.Controls.Add(list);
                    var choose = new Button { Text = "Import selected", Location = new Point(16, 303), Size = new Size(158, 38), DialogResult = DialogResult.OK };
                    var manual = new Button { Text = "Choose folder...", Location = new Point(185, 303), Size = new Size(150, 38), DialogResult = DialogResult.Retry };
                    selection.Controls.Add(choose);
                    selection.Controls.Add(manual);
                    selection.AcceptButton = choose;
                    var result = selection.ShowDialog(FindForm());
                    if (result == DialogResult.Retry) { await ImportViaPickerAsync(true); return; }
                    if (result == DialogResult.OK && list.SelectedItem != null)
                        await ImportAsync(list.SelectedItem.ToString(), true);
                }
            }
            catch (Exception ex) { if (!IsDisposed) Say("Scan failed: " + ex.Message); }
            finally { working = false; }
        }
        private async Task ImportViaPickerAsync(bool mods)
        {
            using (var dialog = new FolderBrowserDialog
            {
                Description = "Select an existing OctoWoW / Turtle WoW folder or extracted patch pack",
                ShowNewFolderButton = false
            })
            {
                if (dialog.ShowDialog(FindForm()) == DialogResult.OK)
                    await ImportAsync(dialog.SelectedPath, mods);
            }
        }
        private async Task ImportAsync(string folder, bool mods)
        {
            if (Process.GetProcessesByName("WoW").Length > 0)
            {
                Say("Close WoW before importing mods.");
                return;
            }
            string prompt = "Import addons from:\n" + folder +
                "\n\nAddon folders are backed up before replacement.\n\n" +
                "Also copy recognized client DLLs, VanillaFixes and MPQ/HD patches? These can make an older/modified client crash.";
            var result = MessageBox.Show(prompt, "Import addons and client extensions",
                MessageBoxButtons.YesNoCancel, MessageBoxIcon.Warning);
            if (result == DialogResult.Cancel) return;
            Say("Importing existing addons and optional client files...");
            try
            {
                var summary = await AddonFiles.ImportLocalDetailedAsync(folder, wowPath(),
                    result == DialogResult.Yes);
                if (!IsDisposed)
                {
                    Say(summary.Describe() + " Restart WoW to load new addons.");
                    if (summary.Warnings.Count > 0)
                        MessageBox.Show(String.Join(Environment.NewLine, summary.Warnings),
                            "Import completed with skipped items", MessageBoxButtons.OK,
                            MessageBoxIcon.Information);
                    if (page == "Installed") Render();
                }
            }
            catch (Exception ex) { if (!IsDisposed) Say("Import failed: " + ex.Message); }
        }
    }

    internal sealed class AddonDetails : Form
    {
        private readonly AddonEntry entry;
        private readonly FlowLayoutPanel screenshots;
        private readonly RichTextBox readme;
        private readonly Label note;
        internal AddonDetails(AddonEntry selected, Func<Task> onInstall)
        {
            entry = selected;
            Text = selected.Name + " · Addon details";
            Size = new Size(900, 750);
            MinimumSize = new Size(760, 650);
            StartPosition = FormStartPosition.CenterParent;
            BackColor = Color.FromArgb(12, 18, 28);
            ForeColor = Color.White;
            Font = new Font("Segoe UI", 10);
            var heading = new Label
            {
                Text = selected.Name, Location = new Point(23, 16),
                Size = new Size(735, 39), Font = new Font("Segoe UI", 20, FontStyle.Bold),
                ForeColor = Color.White
            };
            Controls.Add(heading);
            var blurb = new Label
            {
                Text = selected.Description + "\n" + selected.Source + " · " + selected.Author +
                    " · ★ " + selected.Stars,
                Location = new Point(23, 59), Size = new Size(760, 70),
                ForeColor = Color.FromArgb(173, 196, 211), AutoEllipsis = true
            };
            Controls.Add(blurb);
            readme = new RichTextBox
            {
                Location = new Point(23, 143), Size = new Size(835, 315),
                Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right,
                BackColor = Color.FromArgb(24, 36, 50), ForeColor = Color.White,
                BorderStyle = BorderStyle.None, ReadOnly = true,
                DetectUrls = true, Text = "Loading project README and screenshots..."
            };
            Controls.Add(readme);
            screenshots = new FlowLayoutPanel
            {
                Location = new Point(23, 483), Size = new Size(835, 151),
                Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Bottom,
                AutoScroll = true, WrapContents = false, FlowDirection = FlowDirection.LeftToRight
            };
            Controls.Add(screenshots);
            var install = new Button
            {
                Text = "Install addon", Location = new Point(23, 654), Size = new Size(230, 43),
                Anchor = AnchorStyles.Bottom | AnchorStyles.Left,
                BackColor = Color.FromArgb(98, 232, 190), ForeColor = Color.Black,
                FlatStyle = FlatStyle.Flat
            };
            install.Click += async (s, e) =>
            {
                install.Enabled = false;
                try { await onInstall(); }
                finally { if (!IsDisposed) install.Enabled = true; }
            };
            Controls.Add(install);
            var source = new Button
            {
                Text = "Open original website", Location = new Point(265, 654), Size = new Size(230, 43),
                Anchor = AnchorStyles.Bottom | AnchorStyles.Left,
                BackColor = Color.FromArgb(42, 63, 82), ForeColor = Color.White, FlatStyle = FlatStyle.Flat
            };
            source.Click += (s, e) => { if (entry.Url.StartsWith("https://"))
                Process.Start(new ProcessStartInfo(entry.Url) { UseShellExecute = true }); };
            Controls.Add(source);
            note = new Label { Text = "", Location = new Point(23, 704), Size = new Size(830, 18),
                Anchor = AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right,
                ForeColor = Color.FromArgb(163, 185, 203) };
            Controls.Add(note);
            Shown += async (s, e) => await LoadReadmeAsync();
        }
        private async Task LoadReadmeAsync()
        {
            var match = Regex.Match(entry.Url ?? "",
                @"^https://github\.com/([^/]+)/([^/]+?)(?:\.git)?/?$", RegexOptions.IgnoreCase);
            if (!match.Success)
            {
                AddonMarkdown.Render(readme, entry.Description +
                    "\n\nFull documentation is available on the original website.");
                note.Text = "This source does not have a supported GitHub README.";
                return;
            }
            string owner = match.Groups[1].Value, repo = match.Groups[2].Value;
            try
            {
                var data = await Task.Run(() =>
                {
                    string branch = "main";
                    using (var web = AddonCatalog.NewClient())
                    {
                        try
                        {
                            var metadata = new System.Web.Script.Serialization.JavaScriptSerializer()
                                .DeserializeObject(web.DownloadString(
                                    "https://api.github.com/repos/" + owner + "/" + repo))
                                    as Dictionary<string, object>;
                            object value;
                            if (metadata != null && metadata.TryGetValue("default_branch", out value))
                                branch = Convert.ToString(value);
                        }
                        catch (WebException) { /* README fetch below can still work. */ }
                        web.Headers[HttpRequestHeader.Accept] = "application/vnd.github.raw+json";
                        string markdown = web.DownloadString(
                            "https://api.github.com/repos/" + owner + "/" + repo + "/readme");
                        if (markdown.TrimStart().StartsWith("{") && markdown.Contains("\"encoding\""))
                        {
                            // GitHub may serve JSON despite the raw Accept header.
                            var obj = new System.Web.Script.Serialization.JavaScriptSerializer()
                                .DeserializeObject(markdown) as Dictionary<string, object>;
                            object value;
                            if (obj != null && obj.TryGetValue("encoding", out value) &&
                                Convert.ToString(value) == "base64" && obj.TryGetValue("content", out value))
                                markdown = System.Text.Encoding.UTF8.GetString(Convert.FromBase64String(
                                    Convert.ToString(value).Replace("\r", "").Replace("\n", "")));
                        }
                        return Tuple.Create(markdown,
                            "https://raw.githubusercontent.com/" + owner + "/" + repo + "/" + branch + "/");
                    }
                });
                if (IsDisposed) return;
                string markdown = data.Item1.Length > 50000 ? data.Item1.Substring(0, 50000) : data.Item1;
                AddonMarkdown.Render(readme, markdown);
                var images = AddonMarkdown.ImageUrls(data.Item1, data.Item2);
                screenshots.Controls.Clear();
                foreach (var uri in images)
                {
                    var pic = new PictureBox
                    {
                        Size = new Size(228, 140), SizeMode = PictureBoxSizeMode.Zoom,
                        BackColor = Color.FromArgb(40, 57, 72), Cursor = Cursors.Hand,
                        Margin = new Padding(0, 0, 9, 5)
                    };
                    string link = uri;
                    pic.Click += (s, e) => Process.Start(
                        new ProcessStartInfo(link) { UseShellExecute = true });
                    pic.LoadCompleted += (s, e) =>
                    {
                        if (e.Error != null || e.Cancelled)
                        {
                            pic.Image = null;
                            pic.BackColor = Color.FromArgb(58, 70, 79);
                        }
                    };
                    screenshots.Controls.Add(pic);
                    try { pic.LoadAsync(uri); } catch { }
                }
                note.Text = images.Count == 0
                    ? "No screenshots in the project's README."
                    : images.Count + " screenshots from GitHub README. Click to open the original image.";
            }
            catch (Exception ex)
            {
                if (IsDisposed) return;
                AddonMarkdown.Render(readme, entry.Description +
                    "\n\nOpen the original website to read the full documentation.");
                note.Text = "README could not be loaded: " + ex.Message;
            }
        }
    }
}
