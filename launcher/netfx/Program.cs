using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace CodexSub2APIInstallerNetFx
{
    internal static class Program
    {
        [STAThread]
        private static int Main(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            try
            {
                string workDir = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "Sub2API Codex Installer");
                Directory.CreateDirectory(workDir);

                string scriptPath = Path.Combine(workDir, "setup-codex-sub2api.ps1");
                ExtractResource("setup-codex-sub2api.ps1", scriptPath);

                string logPath = GetWritableLogPath(workDir);
                File.AppendAllText(logPath, "[" + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "] Starting Codex Sub2API installer exe" + Environment.NewLine, Encoding.UTF8);

                string ps = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe");
                if (!File.Exists(ps)) ps = "powershell.exe";

                ProcessStartInfo psi = new ProcessStartInfo();
                psi.FileName = ps;
                psi.Arguments = BuildPowerShellArguments(scriptPath, args);
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;
                psi.RedirectStandardOutput = true;
                psi.RedirectStandardError = true;
                psi.WorkingDirectory = workDir;

                using (Process proc = new Process())
                {
                    proc.StartInfo = psi;
                    proc.Start();
                    string output = proc.StandardOutput.ReadToEnd();
                    string error = proc.StandardError.ReadToEnd();
                    proc.WaitForExit();

                    if (!String.IsNullOrWhiteSpace(output)) File.AppendAllText(logPath, output + Environment.NewLine, Encoding.UTF8);
                    if (!String.IsNullOrWhiteSpace(error)) File.AppendAllText(logPath, error + Environment.NewLine, Encoding.UTF8);

                    if (proc.ExitCode != 0)
                    {
                        MessageBox.Show("安装器启动失败，错误码：" + proc.ExitCode + "\n\n日志位置：" + logPath,
                            "Codex 安装器", MessageBoxButtons.OK, MessageBoxIcon.Error);
                    }
                    return proc.ExitCode;
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show(ex.ToString(), "Codex 安装器启动失败", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 1;
            }
        }

        private static string BuildPowerShellArguments(string scriptPath, string[] args)
        {
            StringBuilder builder = new StringBuilder();
            builder.Append("-NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File ");
            builder.Append(Quote(scriptPath));
            builder.Append(" -Gui");
            foreach (string arg in args)
            {
                builder.Append(' ');
                builder.Append(Quote(arg));
            }
            return builder.ToString();
        }

        private static string Quote(string value)
        {
            return "\"" + value.Replace("\"", "\\\"") + "\"";
        }

        private static void ExtractResource(string resourceName, string destinationPath)
        {
            Assembly asm = Assembly.GetExecutingAssembly();
            using (Stream stream = asm.GetManifestResourceStream(resourceName))
            {
                if (stream == null) throw new InvalidOperationException("Missing embedded resource: " + resourceName);
                using (FileStream file = File.Create(destinationPath))
                {
                    stream.CopyTo(file);
                }
            }
        }

        private static string GetWritableLogPath(string fallbackDir)
        {
            string exeDir = AppDomain.CurrentDomain.BaseDirectory;
            try
            {
                string path = Path.Combine(exeDir, "install-error.log");
                File.AppendAllText(path, String.Empty, Encoding.UTF8);
                return path;
            }
            catch
            {
                return Path.Combine(fallbackDir, "install-error.log");
            }
        }
    }
}
