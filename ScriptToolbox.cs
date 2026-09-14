using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using System.Web.Script.Serialization;
using System.Windows.Forms;

namespace ScriptToolbox
{
    public sealed class ToolItem
    {
        public string Name { get; set; }
        public string Path { get; set; }
    }

    internal sealed class ToolboxForm : Form
    {
        private static readonly IntPtr HwndTopmost = new IntPtr(-1);
        private static readonly IntPtr HwndNotopmost = new IntPtr(-2);
        private const uint SwpNoSize = 0x0001;
        private const uint SwpNoMove = 0x0002;
        private const uint SwpShowWindow = 0x0040;

        [DllImport("user32.dll")]
        private static extern bool SetForegroundWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        private static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int x, int y, int cx, int cy, uint flags);

        private const string LauncherBatchName = "脚本工具箱.bat";
        private const string LauncherExeName = "ScriptToolbox.exe";
        private readonly string appDirectory;
        private readonly string configPath;
        private readonly JavaScriptSerializer serializer = new JavaScriptSerializer();
        private readonly List<ToolItem> tools;
        private readonly ListView list = new ListView();
        private ListViewItem draggedItem;

        private readonly Button runButton = new Button { Text = "运行选中工具" };
        private readonly Button addButton = new Button { Text = "添加工具..." };
        private readonly Button renameButton = new Button { Text = "重命名" };
        private readonly Button removeButton = new Button { Text = "从列表移除" };
        private readonly Button folderButton = new Button { Text = "打开工具文件夹" };
        private readonly Button upButton = new Button { Text = "上移" };
        private readonly Button downButton = new Button { Text = "下移" };
        private readonly Button refreshButton = new Button { Text = "刷新" };

        public ToolboxForm()
        {
            appDirectory = AppDomain.CurrentDomain.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
            configPath = Path.Combine(appDirectory, "ToolLauncher.tools.json");
            tools = LoadTools();

            Text = "脚本工具箱";
            StartPosition = FormStartPosition.CenterScreen;
            Size = new Size(860, 520);
            MinimumSize = new Size(760, 400);
            Font = new Font("Microsoft YaHei UI", 9F);

            var description = new Label
            {
                Text = "支持 .bat、.py、.exe。双击或点击“运行”启动工具；重命名只改变显示名称；可拖动整行或用上移/下移调整顺序。",
                Location = new Point(16, 16),
                Size = new Size(810, 42),
                Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right
            };
            Controls.Add(description);

            list.Location = new Point(16, 65);
            list.Size = new Size(810, 330);
            list.Anchor = AnchorStyles.Top | AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right;
            list.View = View.Details;
            list.FullRowSelect = true;
            list.GridLines = true;
            list.HideSelection = false;
            list.LabelEdit = true;
            list.AllowDrop = true;
            list.Columns.Add("工具名称", 230);
            list.Columns.Add("工具文件路径", 550);
            Controls.Add(list);

            PlaceButton(runButton, 16, 120);
            PlaceButton(addButton, 144, 100);
            PlaceButton(renameButton, 252, 85);
            PlaceButton(removeButton, 345, 105);
            PlaceButton(folderButton, 458, 135);
            PlaceButton(upButton, 601, 55);
            PlaceButton(downButton, 664, 55);
            refreshButton.Location = new Point(698, 412);
            refreshButton.Size = new Size(128, 34);
            refreshButton.Anchor = AnchorStyles.Bottom | AnchorStyles.Right;
            Controls.Add(refreshButton);

            runButton.Click += delegate { RunSelectedTool(); };
            addButton.Click += delegate { AddTools(); };
            renameButton.Click += delegate { RenameSelectedTool(); };
            removeButton.Click += delegate { RemoveSelectedTool(); };
            folderButton.Click += delegate { OpenSelectedToolFolder(); };
            upButton.Click += delegate { MoveSelectedTool(-1); };
            downButton.Click += delegate { MoveSelectedTool(1); };
            refreshButton.Click += delegate { RefreshTools(); };
            list.DoubleClick += delegate { RunSelectedTool(); };
            list.KeyDown += ListKeyDown;
            list.AfterLabelEdit += ListAfterLabelEdit;
            list.ItemDrag += ListItemDrag;
            list.DragEnter += ListDragEnter;
            list.DragOver += ListDragOver;
            list.DragDrop += ListDragDrop;
            Shown += delegate { BeginInvoke(new Action(BringToFrontOnStartup)); };

            RenderList(null);
        }

        private void BringToFrontOnStartup()
        {
            WindowState = FormWindowState.Normal;
            SetWindowPos(Handle, HwndTopmost, 0, 0, 0, 0, SwpNoSize | SwpNoMove | SwpShowWindow);
            Activate();
            BringToFront();
            TopMost = true;
            SetForegroundWindow(Handle);
            Focus();

            var releaseTimer = new Timer { Interval = 800 };
            releaseTimer.Tick += delegate
            {
                releaseTimer.Stop();
                SetWindowPos(Handle, HwndNotopmost, 0, 0, 0, 0, SwpNoSize | SwpNoMove | SwpShowWindow);
                TopMost = false;
                Activate();
                SetForegroundWindow(Handle);
                releaseTimer.Dispose();
            };
            releaseTimer.Start();
        }

        private void PlaceButton(Button button, int x, int width)
        {
            button.Location = new Point(x, 412);
            button.Size = new Size(width, 34);
            button.Anchor = AnchorStyles.Bottom | AnchorStyles.Left;
            Controls.Add(button);
        }

        private List<ToolItem> LoadTools()
        {
            if (File.Exists(configPath))
            {
                try
                {
                    var loaded = serializer.Deserialize<List<ToolItem>>(File.ReadAllText(configPath));
                    if (loaded != null)
                    {
                        return loaded
                            .Where(tool => tool != null && !String.IsNullOrWhiteSpace(tool.Path) && File.Exists(tool.Path) &&
                                           IsSupportedTool(tool.Path) && !IsLauncherFile(tool.Path))
                            .Select(NormalizeTool)
                            .ToList();
                    }
                }
                catch (Exception exception)
                {
                    MessageBox.Show("工具列表无法读取，将扫描本目录。\r\n" + exception.Message, "脚本工具箱", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                }
            }

            return Directory.EnumerateFiles(appDirectory)
                .Where(IsSupportedTool)
                .Where(path => !IsLauncherFile(path))
                .OrderBy(path => Path.GetFileName(path), StringComparer.CurrentCultureIgnoreCase)
                .Select(path => new ToolItem { Name = Path.GetFileNameWithoutExtension(path), Path = path })
                .ToList();
        }

        private static bool IsSupportedTool(string path)
        {
            var extension = Path.GetExtension(path);
            return String.Equals(extension, ".bat", StringComparison.OrdinalIgnoreCase) ||
                   String.Equals(extension, ".py", StringComparison.OrdinalIgnoreCase) ||
                   String.Equals(extension, ".exe", StringComparison.OrdinalIgnoreCase);
        }

        private static bool IsLauncherFile(string path)
        {
            var fileName = Path.GetFileName(path);
            return String.Equals(fileName, LauncherBatchName, StringComparison.OrdinalIgnoreCase) ||
                   String.Equals(fileName, LauncherExeName, StringComparison.OrdinalIgnoreCase);
        }

        private static ToolItem NormalizeTool(ToolItem tool)
        {
            tool.Name = String.IsNullOrWhiteSpace(tool.Name) ? Path.GetFileNameWithoutExtension(tool.Path) : tool.Name.Trim();
            return tool;
        }

        private bool SaveTools()
        {
            try
            {
                File.WriteAllText(configPath, serializer.Serialize(tools));
                return true;
            }
            catch (Exception exception)
            {
                MessageBox.Show("无法保存工具列表：\r\n" + exception.Message, "脚本工具箱", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return false;
            }
        }

        private void RenderList(ToolItem selectTool)
        {
            list.BeginUpdate();
            list.Items.Clear();
            foreach (var tool in tools)
            {
                var item = new ListViewItem(tool.Name) { Tag = tool };
                item.SubItems.Add(tool.Path);
                list.Items.Add(item);
                if (Object.ReferenceEquals(tool, selectTool))
                {
                    item.Selected = true;
                    item.Focused = true;
                }
            }
            list.EndUpdate();
        }

        private ToolItem GetSelectedTool()
        {
            return list.SelectedItems.Count == 0 ? null : list.SelectedItems[0].Tag as ToolItem;
        }

        private ListViewItem GetSelectedListItem()
        {
            return list.SelectedItems.Count == 0 ? null : list.SelectedItems[0];
        }

        private bool EnsureSelection(out ToolItem tool)
        {
            tool = GetSelectedTool();
            if (tool != null) return true;
            MessageBox.Show("请先选择一个工具。", "脚本工具箱", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return false;
        }

        private void RunSelectedTool()
        {
            ToolItem tool;
            if (!EnsureSelection(out tool)) return;
            if (!File.Exists(tool.Path))
            {
                MessageBox.Show("找不到该文件：\r\n" + tool.Path, "脚本工具箱", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            try
            {
                var extension = Path.GetExtension(tool.Path).ToLowerInvariant();
                if (extension == ".bat")
                {
                    var batchText = File.ReadAllText(tool.Path);
                    var requiresConsole = Regex.IsMatch(batchText, @"(?im)^\s*pause\b");
                    if (requiresConsole)
                    {
                        Process.Start(new ProcessStartInfo(tool.Path) { UseShellExecute = true });
                    }
                    else
                    {
                        StartHidden(tool.Path, Environment.GetEnvironmentVariable("ComSpec"), "/d /s /c \"\"" + tool.Path + "\"\"");
                    }
                }
                else if (extension == ".py")
                {
                    try
                    {
                        StartHidden(tool.Path, "py.exe", "-3 \"" + tool.Path + "\"");
                    }
                    catch (System.ComponentModel.Win32Exception)
                    {
                        StartHidden(tool.Path, "python.exe", "\"" + tool.Path + "\"");
                    }
                }
                else if (extension == ".exe")
                {
                    StartHidden(tool.Path, tool.Path, String.Empty);
                }
                else
                {
                    throw new InvalidOperationException("不支持的工具文件类型：" + extension);
                }
                Close();
            }
            catch (Exception exception)
            {
                MessageBox.Show("无法启动工具：\r\n" + exception.Message, "脚本工具箱", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private static void StartHidden(string toolPath, string executable, string arguments)
        {
            var startInfo = new ProcessStartInfo
            {
                FileName = executable,
                Arguments = arguments,
                WorkingDirectory = Path.GetDirectoryName(toolPath),
                UseShellExecute = false,
                CreateNoWindow = true
            };
            Process.Start(startInfo);
        }

        private void AddTools()
        {
            using (var dialog = new OpenFileDialog())
            {
                dialog.Title = "选择要添加的工具文件";
                dialog.Filter = "工具文件 (*.bat;*.py;*.exe)|*.bat;*.py;*.exe|批处理文件 (*.bat)|*.bat|Python 脚本 (*.py)|*.py|程序 (*.exe)|*.exe";
                dialog.Multiselect = true;
                dialog.InitialDirectory = appDirectory;
                if (dialog.ShowDialog(this) != DialogResult.OK) return;

                ToolItem lastAdded = null;
                foreach (var path in dialog.FileNames)
                {
                    if (tools.Any(tool => String.Equals(tool.Path, path, StringComparison.OrdinalIgnoreCase))) continue;
                    lastAdded = new ToolItem { Name = Path.GetFileNameWithoutExtension(path), Path = path };
                    tools.Add(lastAdded);
                }
                if (SaveTools()) RenderList(lastAdded);
            }
        }

        private void RenameSelectedTool()
        {
            var item = GetSelectedListItem();
            if (item == null)
            {
                MessageBox.Show("请先选择一个工具。", "脚本工具箱", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }
            item.BeginEdit();
        }

        private void ListAfterLabelEdit(object sender, LabelEditEventArgs e)
        {
            if (e.Label == null) return;
            var name = e.Label.Trim();
            if (name.Length == 0)
            {
                e.CancelEdit = true;
                MessageBox.Show("工具名称不能为空。", "脚本工具箱", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }
            var tool = list.Items[e.Item].Tag as ToolItem;
            if (tool == null) return;
            tool.Name = name;
            SaveTools();
        }

        private void RemoveSelectedTool()
        {
            ToolItem tool;
            if (!EnsureSelection(out tool)) return;
            var answer = MessageBox.Show("从工具箱列表移除 [" + tool.Name + "] 吗？\r\n不会删除原始工具文件。", "确认移除", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
            if (answer != DialogResult.Yes) return;
            tools.Remove(tool);
            if (SaveTools()) RenderList(null);
        }

        private void OpenSelectedToolFolder()
        {
            ToolItem tool;
            if (!EnsureSelection(out tool)) return;
            var folder = Path.GetDirectoryName(tool.Path);
            if (String.IsNullOrWhiteSpace(folder) || !Directory.Exists(folder))
            {
                MessageBox.Show("找不到工具所在文件夹：\r\n" + folder, "脚本工具箱", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }
            try
            {
                Process.Start(new ProcessStartInfo("explorer.exe", "/select,\"" + tool.Path + "\"") { UseShellExecute = true });
            }
            catch (Exception exception)
            {
                MessageBox.Show("无法打开工具文件夹：\r\n" + exception.Message, "脚本工具箱", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void MoveSelectedTool(int delta)
        {
            ToolItem tool;
            if (!EnsureSelection(out tool)) return;
            var oldIndex = tools.IndexOf(tool);
            var newIndex = oldIndex + delta;
            if (newIndex < 0 || newIndex >= tools.Count) return;
            tools.RemoveAt(oldIndex);
            tools.Insert(newIndex, tool);
            if (SaveTools()) RenderList(tool);
        }

        private void RefreshTools()
        {
            tools.RemoveAll(tool => !File.Exists(tool.Path));
            SaveTools();
            RenderList(null);
        }

        private void ListKeyDown(object sender, KeyEventArgs e)
        {
            if (e.KeyCode == Keys.F2)
            {
                RenameSelectedTool();
                e.Handled = true;
            }
        }

        private void ListItemDrag(object sender, ItemDragEventArgs e)
        {
            draggedItem = e.Item as ListViewItem;
            if (draggedItem != null) DoDragDrop(draggedItem, DragDropEffects.Move);
        }

        private void ListDragEnter(object sender, DragEventArgs e)
        {
            e.Effect = e.Data.GetDataPresent(typeof(ListViewItem)) ? DragDropEffects.Move : DragDropEffects.None;
        }

        private void ListDragOver(object sender, DragEventArgs e)
        {
            e.Effect = e.Data.GetDataPresent(typeof(ListViewItem)) ? DragDropEffects.Move : DragDropEffects.None;
        }

        private void ListDragDrop(object sender, DragEventArgs e)
        {
            var source = e.Data.GetData(typeof(ListViewItem)) as ListViewItem;
            if (source == null) return;
            var point = list.PointToClient(new Point(e.X, e.Y));
            var target = list.GetItemAt(point.X, point.Y);
            var oldIndex = source.Index;
            var newIndex = target == null ? tools.Count - 1 : target.Index;
            if (target != null && point.Y > target.Bounds.Top + (target.Bounds.Height / 2)) newIndex++;
            if (oldIndex < newIndex) newIndex--;
            if (newIndex < 0) newIndex = 0;
            if (newIndex >= tools.Count) newIndex = tools.Count - 1;
            if (newIndex == oldIndex) return;

            var tool = source.Tag as ToolItem;
            tools.RemoveAt(oldIndex);
            tools.Insert(newIndex, tool);
            if (SaveTools()) RenderList(tool);
        }
    }

    internal static class Program
    {
        [STAThread]
        private static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new ToolboxForm());
        }
    }
}
