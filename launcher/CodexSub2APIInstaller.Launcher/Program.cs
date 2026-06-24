using System.Diagnostics;
using System.Reflection;
using System.Text;
using System.Windows.Forms;

namespace CodexSub2APIInstaller;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);

        try
        {
            var workDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Sub2API Codex Installer");
            Directory.CreateDirectory(workDir);

            var scriptPath = Path.Combine(workDir, "setup-codex-sub2api.ps1");
            ExtractResource("setup-codex-sub2api.ps1", scriptPath);

            var logPath = GetWritableLogPath(workDir);
            File.AppendAllText(logPath, $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] Starting Codex Sub2API installer exe{Environment.NewLine}", Encoding.UTF8);

            var ps = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
                "WindowsPowerShell", "v1.0", "powershell.exe");
            if (!File.Exists(ps))
            {
                ps = "powershell.exe";
            }

            var argLine = BuildPowerShellArguments(scriptPath, args);
            var psi = new ProcessStartInfo
            {
                FileName = ps,
                Arguments = argLine,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                WorkingDirectory = workDir,
                StandardOutputEncoding = Encoding.UTF8,
                StandardErrorEncoding = Encoding.UTF8,
            };

            using var proc = new Process { StartInfo = psi, EnableRaisingEvents = true };
            proc.Start();

            var stdoutTask = proc.StandardOutput.ReadToEndAsync();
            var stderrTask = proc.StandardError.ReadToEndAsync();
            proc.WaitForExit();
            Task.WaitAll(stdoutTask, stderrTask);

            var output = stdoutTask.Result;
            var error = stderrTask.Result;
            if (!string.IsNullOrWhiteSpace(output)) File.AppendAllText(logPath, output + Environment.NewLine, Encoding.UTF8);
            if (!string.IsNullOrWhiteSpace(error)) File.AppendAllText(logPath, error + Environment.NewLine, Encoding.UTF8);

            if (proc.ExitCode != 0)
            {
                MessageBox.Show(
                    $"安装器启动失败，错误码：{proc.ExitCode}\n\n日志位置：{logPath}",
                    "Codex 安装器",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
            }

            return proc.ExitCode;
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.ToString(), "Codex 安装器启动失败", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }

    private static string BuildPowerShellArguments(string scriptPath, string[] args)
    {
        var builder = new StringBuilder();
        builder.Append("-NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File ");
        builder.Append(Quote(scriptPath));
        builder.Append(" -Gui");
        foreach (var arg in args)
        {
            builder.Append(' ');
            builder.Append(Quote(arg));
        }
        return builder.ToString();
    }

    private static string Quote(string value) => "\"" + value.Replace("\"", "\\\"") + "\"";

    private static void ExtractResource(string resourceName, string destinationPath)
    {
        var asm = Assembly.GetExecutingAssembly();
        using var stream = asm.GetManifestResourceStream(resourceName)
            ?? throw new InvalidOperationException($"Missing embedded resource: {resourceName}");
        using var file = File.Create(destinationPath);
        stream.CopyTo(file);
    }

    private static string GetWritableLogPath(string fallbackDir)
    {
        var exeDir = AppContext.BaseDirectory;
        try
        {
            var path = Path.Combine(exeDir, "install-error.log");
            File.AppendAllText(path, string.Empty, Encoding.UTF8);
            return path;
        }
        catch
        {
            return Path.Combine(fallbackDir, "install-error.log");
        }
    }
}
