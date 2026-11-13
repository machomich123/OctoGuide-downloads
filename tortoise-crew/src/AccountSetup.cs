using System;
using System.Drawing;
using System.Text.RegularExpressions;
using System.Windows.Forms;

namespace TortoiseCrew
{
    internal static class AccountSetup
    {
        public static bool Show(IWin32Window parent, LauncherSettings settings, string username)
        {
            if (!Regex.IsMatch(username ?? "", "^(MICHAEL|JAYKE|BERNARD|AUGUST)$"))
            {
                MessageBox.Show("Choose your account first.", "Crew account");
                return false;
            }
            using (var dialog = new Form())
            {
                dialog.Text = "Tortoise Crew - Account and Password";
                dialog.ClientSize = new Size(600, 440);
                dialog.FormBorderStyle = FormBorderStyle.FixedDialog;
                dialog.StartPosition = FormStartPosition.CenterParent;
                dialog.MaximizeBox = false;
                dialog.MinimizeBox = false;
                dialog.BackColor = Color.FromArgb(12, 18, 28);
                dialog.ForeColor = Color.WhiteSmoke;
                dialog.Font = new Font("Segoe UI", 10f);

                var header = new Label { Text = username + " - Account setup",
                    Location = new Point(24, 14), Size = new Size(554, 33),
                    Font = new Font("Segoe UI", 16f, FontStyle.Bold),
                    ForeColor = Color.FromArgb(98, 232, 190) };
                dialog.Controls.Add(header);
                var info = new Label {
                    Text = "Your password is saved using Windows encryption, never in plain text.",
                    Location = new Point(24, 54), Size = new Size(551, 26) };
                dialog.Controls.Add(info);
                var mode = new ComboBox { Location = new Point(24, 91), Size = new Size(540, 30),
                    DropDownStyle = ComboBoxStyle.DropDownList };
                mode.Items.AddRange(new object[] {
                    "Join this realm with a crew invite",
                    "Pair another PC with my existing password",
                    "Change my account password",
                    "Remember my existing password"
                });
                mode.SelectedIndex = (username == "MICHAEL" || username == "BERNARD") ? 2 : 0;
                dialog.Controls.Add(mode);

                Func<string, int, Label> addLabel = (s, y) => {
                    var item = new Label { Text = s, Location = new Point(24, y),
                        Size = new Size(540, 20), ForeColor = Color.LightGray };
                    dialog.Controls.Add(item);
                    return item;
                };
                Func<int, TextBox> addInput = y => {
                    var item = new TextBox { Location = new Point(24, y), Size = new Size(540, 27),
                        UseSystemPasswordChar = true, Font = new Font("Segoe UI", 11f) };
                    dialog.Controls.Add(item);
                    return item;
                };
                var oldLabel = addLabel("Current account password", 134);
                var oldPass = addInput(155);
                var newLabel = addLabel("New password (12-16 letters and digits)", 191);
                var newPass = addInput(212);
                var confirmLabel = addLabel("Confirm new password", 251);
                var confirm = addInput(272);
                var inviteLabel = addLabel("Crew invitation code", 309);
                var invite = addInput(330);
                var progress = new Label { Text = "", Location = new Point(24, 372),
                    Size = new Size(367, 54), ForeColor = Color.LightGray };
                dialog.Controls.Add(progress);
                var submit = new Button { Text = "SAVE", Location = new Point(406, 372),
                    Size = new Size(160, 44), FlatStyle = FlatStyle.Flat,
                    BackColor = Color.FromArgb(98,232,190), ForeColor = Color.Black };
                dialog.Controls.Add(submit);

                Action updateVisibility = () => {
                    int x = mode.SelectedIndex;
                    oldPass.Visible = oldLabel.Visible = x != 0;
                    newPass.Visible = newLabel.Visible = (x == 0 || x == 2);
                    confirm.Visible = confirmLabel.Visible = (x == 0 || x == 2);
                    invite.Visible = inviteLabel.Visible = x == 0;
                    submit.Text = x == 0 ? "JOIN CREW" : x == 1 ? "PAIR THIS PC" :
                        x == 2 ? "CHANGE PASSWORD" : "REMEMBER";
                    progress.Text = x == 0 ? "Enter the shared one-time crew invite." :
                        x == 1 ? "Use the password you created before." :
                        x == 2 ? "If unchanged, the current password is 1." :
                        "Stores a password you already set on the server.";
                };
                mode.SelectedIndexChanged += (s,e) => updateVisibility();
                updateVisibility();
                bool success = false;

                submit.Click += async (s, e) => {
                    int x = mode.SelectedIndex;
                    string current = oldPass.Text, desired = newPass.Text;
                    if ((x != 0 && !CrewEnrollment.ValidExistingPassword(current)) ||
                        ((x == 0 || x == 2) && (!CrewEnrollment.ValidNewPassword(desired) ||
                                                  desired != confirm.Text)) ||
                        (x == 0 && String.IsNullOrWhiteSpace(invite.Text)))
                    {
                        progress.Text = "Check the password, confirmation and invite code.";
                        return;
                    }
                    if (x == 3)
                    {
                        PasswordVault.Save(username, current);
                        success = true;
                        dialog.DialogResult = DialogResult.OK;
                        dialog.Close();
                        return;
                    }
                    submit.Enabled = false;
                    mode.Enabled = false;
                    progress.Text = "Contacting server securely...";
                    try
                    {
                        string action = x == 0 ? "register" : x == 1 ? "pair" : "change-password";
                        CrewReply reply = await CrewEnrollment.SendAsync(settings, action, username,
                            current, desired, invite.Text.Trim());
                        if (reply == null || !reply.ok)
                        {
                            progress.Text = "Not saved: " + (reply == null ? "UNKNOWN" :
                                (reply.code ?? "UNKNOWN").Replace("_", " "));
                            return;
                        }
                        PasswordVault.Save(username, x == 1 ? current : desired);
                        Paths.WriteLog("Account setup succeeded for " + username + " (" + action + ").");
                        success = true;
                        dialog.DialogResult = DialogResult.OK;
                        dialog.Close();
                    }
                    catch (Exception ex)
                    {
                        Paths.WriteLog("Account setup failed (no secret logged): " + ex.GetType().Name);
                        progress.Text = "Connection failed. Try again.";
                    }
                    finally
                    {
                        if (!dialog.IsDisposed) { submit.Enabled = true; mode.Enabled = true; }
                    }
                };
                dialog.ShowDialog(parent);
                return success;
            }
        }
    }
}
