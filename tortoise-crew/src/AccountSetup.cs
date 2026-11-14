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
        public static bool Show(IWin32Window parent, LauncherSettings settings, string username, bool initial = false)
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
                var newLabel = label("New password (1-16 characters, no strength rules)", 194);
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
                newLabel.Visible = desired.Visible = !initial;
                confirmLabel.Visible = confirm.Visible = !initial;
                detail.Text = initial ? "Enter the account password once." :
                    "Updates your WoW account immediately, without in-game commands.";
                save.Text = initial ? "SAVE PASSWORD" : "DONE";
                bool result = false;
                save.Click += async (s,e) => {
                    if (!CrewEnrollment.ValidExistingPassword(current.Text))
                    {
                        detail.Text = "Enter the current game account password.";
                        return;
                    }
                    if (initial)
                    {
                        if (!String.IsNullOrEmpty(settings.CrewApiUrl))
                            await CrewApi.LoginAsync(settings, username, current.Text);
                        PasswordVault.Save(username, current.Text);
                        result = true;
                        dialog.DialogResult = DialogResult.OK;
                        dialog.Close();
                        return;
                    }
                    if (!CrewEnrollment.ValidNewPassword(desired.Text) ||
                        desired.Text != confirm.Text || desired.Text == current.Text)
                    {
                        detail.Text = "Confirm a different password using up to 16 printable characters.";
                        return;
                    }
                    try
                    {
                        await CrewApi.ChangePasswordAsync(settings, username, current.Text, desired.Text);
                        PasswordVault.Save(username, desired.Text);
                    }
                    catch (Exception ex)
                    {
                        detail.Text = "Password was not changed: " + ex.Message;
                        return;
                    }
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
