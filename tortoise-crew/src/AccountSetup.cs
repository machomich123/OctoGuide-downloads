using System;
using System.Drawing;
using System.Text.RegularExpressions;
using System.Windows.Forms;

namespace TortoiseCrew
{
    // This dialog never sends credentials through Altare's SSH gateway:
    // the gateway does not enforce authorized_keys forced-command restrictions.
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
                dialog.Text = "Tortoise Crew - Personal Password";
                dialog.ClientSize = new Size(600, 387);
                dialog.FormBorderStyle = FormBorderStyle.FixedDialog;
                dialog.StartPosition = FormStartPosition.CenterParent;
                dialog.MaximizeBox = false;
                dialog.MinimizeBox = false;
                dialog.BackColor = Color.FromArgb(12,18,28);
                dialog.ForeColor = Color.WhiteSmoke;
                dialog.Font = new Font("Segoe UI",10f);
                var heading = new Label { Text = username + " - Personal password",
                    Location = new Point(24,14), Size = new Size(540,34),
                    ForeColor = Color.FromArgb(98,232,190),
                    Font = new Font("Segoe UI",16f,FontStyle.Bold) };
                dialog.Controls.Add(heading);
                dialog.Controls.Add(new Label {
                    Text = "Passwords are encrypted locally with Windows DPAPI.",
                    Location = new Point(24,53), Size = new Size(540,25) });
                var mode = new ComboBox {
                    Location = new Point(24,89), Size = new Size(540,30),
                    DropDownStyle = ComboBoxStyle.DropDownList
                };
                mode.Items.AddRange(new object[] {
                    "Remember my existing account password",
                    "Change my password using the in-game command"
                });
                mode.SelectedIndex = 0;
                dialog.Controls.Add(mode);
                Func<string,int,Label> label = (text,y) => {
                    var l = new Label { Text=text, Location=new Point(24,y),
                        Size=new Size(540,21), ForeColor=Color.LightGray };
                    dialog.Controls.Add(l);
                    return l;
                };
                Func<int,TextBox> passwordBox = y => {
                    var t = new TextBox { Location=new Point(24,y), Size=new Size(540,28),
                        UseSystemPasswordChar=true, Font=new Font("Segoe UI",11f) };
                    dialog.Controls.Add(t);
                    return t;
                };
                var oldLabel = label("Current game account password", 129);
                var current = passwordBox(151);
                var newLabel = label("Choose a new password (12-16 letters and digits)", 194);
                var desired = passwordBox(216);
                var confirmLabel = label("Confirm your new password", 252);
                var confirm = passwordBox(274);
                var detail = new Label { Location=new Point(24,326), Size=new Size(364,48),
                    ForeColor=Color.LightGray };
                dialog.Controls.Add(detail);
                var save = new Button { Text="SAVE PASSWORD", Location=new Point(407,325),
                    Size=new Size(158,44), FlatStyle=FlatStyle.Flat,
                    BackColor=Color.FromArgb(98,232,190),ForeColor=Color.Black };
                dialog.Controls.Add(save);
                Action refresh = () => {
                    bool change = mode.SelectedIndex == 1;
                    newLabel.Visible = desired.Visible = change;
                    confirmLabel.Visible = confirm.Visible = change;
                    detail.Text = change
                        ? "A game chat command is copied. Run it inside WoW to activate the new password."
                        : "Save the password already active on the server (use 1 only before changing it).";
                    save.Text = change ? "COPY COMMAND" : "SAVE PASSWORD";
                };
                mode.SelectedIndexChanged += (s,e) => refresh();
                refresh();
                bool result = false;
                save.Click += (s,e) => {
                    if (!CrewEnrollment.ValidExistingPassword(current.Text))
                    {
                        detail.Text = "Enter the current game account password.";
                        return;
                    }
                    if (mode.SelectedIndex == 0)
                    {
                        PasswordVault.Save(username, current.Text);
                        result = true;
                        dialog.DialogResult = DialogResult.OK;
                        dialog.Close();
                        return;
                    }
                    if (!CrewEnrollment.ValidNewPassword(desired.Text) ||
                        desired.Text != confirm.Text || desired.Text == current.Text)
                    {
                        detail.Text = "Use 12-16 letters/digits, confirm the new password and make it different.";
                        return;
                    }
                    // Safe, native MaNGOS command authenticated as the currently logged-in player.
                    // The new password is NOT stored until the player confirms server-side success.
                    string command = ".account password " + current.Text + " " +
                                     desired.Text + " " + desired.Text;
                    Clipboard.SetText(command);
                    PasswordVault.Save(username, current.Text);
                    MessageBox.Show(dialog,
                        "The password-change command was copied.\n\n" +
                        "1. Start WoW and enter the world using your CURRENT password.\n" +
                        "2. Paste the command into the in-game chat and press Enter.\n" +
                        "3. After the server confirms the change, reopen this dialog and choose " +
                        "'Remember my existing account password' to save your NEW password.\n\n" +
                        "The launcher cannot confirm the change until you complete it in game.",
                        "Finish changing your game password",
                        MessageBoxButtons.OK, MessageBoxIcon.Information);
                    result = true;
                    dialog.DialogResult = DialogResult.OK;
                    dialog.Close();
                };
                dialog.ShowDialog(parent);
                return result;
            }
        }
    }
}
