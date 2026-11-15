using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Windows.Forms;
using System.Xml;
using Microsoft.Win32;

namespace DialDeploy {
    internal sealed class DiskChoice {
        public int Number; public string Model; public string Fingerprint; public long Size;
        public override string ToString() { return String.Format("Disco {0}  ·  {1:0} GB  ·  {2}", Number, Size / 1000000000d, Model); }
    }
    internal sealed class ActivityBar : Control {
        readonly Timer timer = new Timer(); int phase;
        public ActivityBar() {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer, true);
            timer.Interval = 24; timer.Tick += delegate { phase = (phase + 9) % Math.Max(1,Width + 180); Invalidate(); };
            timer.Start();
        }
        protected override void OnPaint(PaintEventArgs e) {
            e.Graphics.Clear(Color.FromArgb(222,232,244));
            using (Brush b = new SolidBrush(Color.FromArgb(17,97,170))) e.Graphics.FillRectangle(b, phase-180,0,180,Height);
        }
        protected override void Dispose(bool disposing) { if (disposing) timer.Dispose(); base.Dispose(disposing); }
    }
    internal sealed class Card : Panel {
        public Card() { BackColor = Color.White; SetStyle(ControlStyles.OptimizedDoubleBuffer,true); }
        protected override void OnPaint(PaintEventArgs e) { base.OnPaint(e); using (var pen = new Pen(Color.FromArgb(213,224,236))) e.Graphics.DrawRectangle(pen,0,0,Width-1,Height-1); }
    }
    internal sealed class MainWindow : Form {
        static readonly Color Blue = Color.FromArgb(17,97,170), Ink = Color.FromArgb(20,42,64), Muted = Color.FromArgb(90,109,129);
        readonly bool preview; readonly string renderPath; readonly bool renderLoading;
        readonly PictureBox logo = new PictureBox();
        readonly Label brand = new Label(), tag = new Label(), kicker = new Label(), heading = new Label(), description = new Label(), computer = new Label();
        readonly Label cardTitle = new Label(), diskLabel = new Label(), note = new Label(), status = new Label(), footer = new Label();
        readonly ComboBox disks = new ComboBox(); readonly Button quick = new Button(), traditional = new Button(), retry = new Button();
        readonly Card card = new Card(); readonly ActivityBar activity = new ActivityBar();
        readonly Panel accent = new Panel();
        readonly Dictionary<string,Font> fonts = new Dictionary<string,Font>();
        string mediaFingerprint; bool busy; bool loading = true;
        float scale = 1;
        public MainWindow(bool previewMode,string screenshotPath,bool loadingScreenshot) {
            preview=previewMode;renderPath=screenshotPath;renderLoading=loadingScreenshot;
            Text="DNW - Batch Formatting"; BackColor=Color.FromArgb(241,246,251);
            AutoScaleMode=AutoScaleMode.None; ClientSize=new Size(1120,720); MinimumSize=new Size(900,620);
            StartPosition=FormStartPosition.CenterScreen; FormBorderStyle=FormBorderStyle.None; DoubleBuffered=true;
            if (!preview) WindowState=FormWindowState.Maximized;
            if (renderPath!=null) { StartPosition=FormStartPosition.Manual; Location=new Point(-32000,-32000); ShowInTaskbar=false; }
            logo.SizeMode=PictureBoxSizeMode.Zoom; logo.BackColor=Color.White;
            string logoPath=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"dial-logo.png");
            if (File.Exists(logoPath)) logo.Image=Image.FromFile(logoPath);
            brand.Text="BATCH FORMATTING"; tag.Text="WINDOWS 11 PRO  /  USB OFFLINE";
            kicker.Text="PREPARAÇÃO DE EQUIPAMENTOS"; heading.Text="Windows limpo.\nPronto para usar.";
            description.Text="Português do Brasil · teclado ABNT2\nConta local User, sem senha.";
            computer.Text="Identificando este computador…";
            cardTitle.Text="Como você quer instalar?"; diskLabel.Text="DISCO DE DESTINO";
            note.Text="A instalação rápida apaga todo o disco selecionado.\nConfira o destino antes de continuar.";
            footer.Text=preview?"PRÉVIA VISUAL · nenhuma instalação será executada":"DIAL NETWORK  ·  Mantenha o pendrive conectado durante a instalação.";
            status.Text="Preparando o ambiente de instalação…";
            disks.DropDownStyle=ComboBoxStyle.DropDownList; disks.FlatStyle=FlatStyle.Flat;
            quick.Text="Instalação rápida   →"; traditional.Text="Instalação tradicional"; retry.Text="Verificar novamente";
            StyleButton(quick,Blue,Color.White); StyleButton(traditional,Color.White,Blue); StyleButton(retry,Color.White,Blue);
            traditional.FlatAppearance.BorderColor=Color.FromArgb(186,205,224); traditional.FlatAppearance.BorderSize=1;
            retry.FlatAppearance.BorderSize=0; retry.Visible=false;
            accent.BackColor=Color.FromArgb(255,206,44);
            foreach (Control control in new Control[]{logo,brand,tag,kicker,heading,description,computer,card,accent,status,activity,footer,retry}) Controls.Add(control);
            foreach (Control control in new Control[]{cardTitle,diskLabel,disks,note,quick,traditional}) card.Controls.Add(control);
            foreach(Label l in new Label[]{brand,tag,kicker,heading,description,computer,cardTitle,diskLabel,note,status,footer}) { l.ForeColor=Ink; l.BackColor=Color.Transparent; }
            tag.ForeColor=Muted; kicker.ForeColor=Blue; description.ForeColor=Muted; computer.ForeColor=Muted; diskLabel.ForeColor=Muted; note.ForeColor=Muted; footer.ForeColor=Muted;
            quick.Enabled=false;traditional.Enabled=false; disks.Enabled=false;
            quick.Click += delegate { BeginInstall("Quick"); }; traditional.Click += delegate { BeginInstall("Traditional"); };
            retry.Click += delegate { LoadInventory(); };
            FormClosing += delegate(object sender,FormClosingEventArgs e) { if (busy && !preview) e.Cancel=true; };
            Shown += delegate {
                if (preview) {
                    LoadPreview();
                    if (renderLoading) { SetBusy(true,"Preparando a instalação rápida…"); }
                    if (renderPath!=null) { var t=new Timer(); t.Interval=400; t.Tick += delegate { t.Stop(); using(var bitmap=new Bitmap(Width,Height)) { DrawToBitmap(bitmap,new Rectangle(0,0,Width,Height)); bitmap.Save(renderPath,ImageFormat.Png); } Close(); t.Dispose(); }; t.Start(); }
                } else LoadInventory();
            };
        }
        static void StyleButton(Button button,Color back,Color fore) { button.BackColor=back;button.ForeColor=fore;button.FlatStyle=FlatStyle.Flat;button.FlatAppearance.BorderSize=0;button.Cursor=Cursors.Hand;button.UseVisualStyleBackColor=false; }
        void Place(Control c,int x,int y,int w,int h,bool inner=false) { int offsetX=inner?0:(ClientSize.Width-(int)(1120*scale))/2;int offsetY=inner?0:(ClientSize.Height-(int)(720*scale))/2;c.SetBounds(offsetX+(int)(x*scale),offsetY+(int)(y*scale),(int)(w*scale),(int)(h*scale)); }
        void Type(Control c,float size,bool bold=false) { string key=(size*scale).ToString("0.00",System.Globalization.CultureInfo.InvariantCulture)+(bold?"B":"R");Font font;if(!fonts.TryGetValue(key,out font)){font=new Font("Tahoma",Math.Max(8,size*scale),bold?FontStyle.Bold:FontStyle.Regular);fonts.Add(key,font);}c.Font=font; }
        protected override void OnLayout(LayoutEventArgs e) {
            base.OnLayout(e);if(card==null)return;scale=Math.Min(ClientSize.Width/1120f,ClientSize.Height/720f);
            Place(logo,46,25,184,87);Place(brand,262,49,300,22);Place(tag,738,52,342,25);Place(accent,46,132,1028,4);
            Place(kicker,46,202,455,23);Place(heading,42,242,500,126);Place(description,46,390,470,70);Place(computer,46,490,470,72);
            Place(card,570,192,504,397);Place(cardTitle,28,27,450,37,true);Place(diskLabel,28,85,450,22,true);Place(disks,28,114,448,36,true);
            Place(note,28,163,448,57,true);Place(quick,28,238,448,61,true);Place(traditional,28,313,448,55,true);
            Place(status,46,619,830,25);Place(retry,881,611,193,34);Place(activity,46,657,1028,5);Place(footer,46,681,1028,24);
            Type(brand,11,true);Type(tag,9,true);Type(kicker,10,true);Type(heading,34,true);Type(description,13);Type(computer,10);Type(cardTitle,19,true);Type(diskLabel,9,true);Type(disks,11);Type(note,10);Type(quick,14,true);Type(traditional,12,true);Type(status,11);Type(retry,10);Type(footer,9);
        }
        protected override void OnPaint(PaintEventArgs e) { base.OnPaint(e);e.Graphics.FillRectangle(Brushes.White,0,0,ClientSize.Width,(int)(151*scale)+(ClientSize.Height-(int)(720*scale))/2); }
        void SetBusy(bool value,string message) {
            busy=value;status.Text=message;activity.Visible=value;status.ForeColor=Ink;
            disks.Enabled=!value;quick.Enabled=!value&&disks.Items.Count>0;traditional.Enabled=!value&&!loading;retry.Visible=false;
        }
        void Error(string message) { loading=false;SetBusy(false,message);status.ForeColor=Color.FromArgb(164,47,39);quick.Enabled=false;traditional.Enabled=false;retry.Visible=true; }
        void LoadPreview() { loading=false;disks.Items.Clear();disks.Items.Add(new DiskChoice{Number=0,Model="SSD NVMe",Size=512000000000,Fingerprint="PREVIEW"});disks.SelectedIndex=0;computer.Text="Equipamento identificado\nComputador x64 · SSD NVMe";SetBusy(false,"Tudo pronto. Escolha uma opção para começar."); }
        static bool InWinPE() { using(var key=Registry.LocalMachine.OpenSubKey(@"SYSTEM\CurrentControlSet\Control\MiniNT"))return key!=null; }
        static XmlElement ReadResult(string path) { var settings=new XmlReaderSettings();settings.DtdProcessing=DtdProcessing.Prohibit;settings.XmlResolver=null;var doc=new XmlDocument();doc.XmlResolver=null;using(var reader=XmlReader.Create(path,settings))doc.Load(reader);return doc.DocumentElement; }
        static string Quote(string s) { return "\""+s.Replace("\"","\\\"")+"\""; }
        static int Hidden(string executable,string arguments,string log) {
            var start=new ProcessStartInfo(executable,arguments);start.UseShellExecute=false;start.CreateNoWindow=true;start.WindowStyle=ProcessWindowStyle.Hidden;start.RedirectStandardOutput=true;start.RedirectStandardError=true;
            using(var p=Process.Start(start)) { string output=p.StandardOutput.ReadToEnd();string error=p.StandardError.ReadToEnd();p.WaitForExit();if(log!=null)File.WriteAllText(log,output+"\r\n"+error);return p.ExitCode; }
        }
        static XmlElement Backend(string operation,string mode,DiskChoice disk,string media) {
            if(!InWinPE())throw new InvalidOperationException("Inicie pelo pendrive para instalar. O Windows deste computador não foi alterado.");
            string output=@"X:\DNW\result-"+Guid.NewGuid().ToString("N")+".xml";
            string args=@"-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File X:\DNW\Deployment.ps1 -Operation "+operation+" -Mode "+mode+" -ResultPath "+Quote(output);
            if(disk!=null)args+=" -DiskNumber "+disk.Number+" -ExpectedFingerprint "+disk.Fingerprint;
            if(!String.IsNullOrEmpty(media))args+=" -ExpectedMediaFingerprint "+media;
            // No Windows command shell is started. All helpers are background processes.
            string powershell=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),@"WindowsPowerShell\v1.0\powershell.exe");
            int code=Hidden(powershell,args,@"X:\DNW\last-operation.log");
            if(!File.Exists(output))throw new InvalidOperationException("Não foi possível preparar o ambiente. Use Verificar novamente; consulte X:\\DNW\\last-operation.log se necessário.");
            var result=ReadResult(output);if(code!=0||result.GetAttribute("status")=="Error")throw new InvalidOperationException(result.GetAttribute("message"));return result;
        }
        void LoadInventory() {
            if(preview){LoadPreview();return;} loading=true;SetBusy(true,"Identificando a mídia e os discos deste computador…");
            var worker=new BackgroundWorker();worker.DoWork+=delegate(object s,DoWorkEventArgs e){if(!InWinPE())throw new InvalidOperationException("Abra este instalador iniciando o computador pelo pendrive.");Hidden("wpeinit.exe","",@"X:\DNW\wpeinit-output.log");Hidden("wpeutil.exe","SetKeyboardLayout 0416:00010416",null);e.Result=Backend("Inventory","Traditional",null,null);};
            worker.RunWorkerCompleted+=delegate(object s,RunWorkerCompletedEventArgs e){worker.Dispose();if(e.Error!=null){Error(e.Error.Message);return;}var result=(XmlElement)e.Result;mediaFingerprint=result.GetAttribute("mediaFingerprint");disks.Items.Clear();foreach(XmlElement item in result.SelectNodes("disk"))disks.Items.Add(new DiskChoice{Number=Int32.Parse(item.GetAttribute("number")),Model=item.GetAttribute("model"),Size=Int64.Parse(item.GetAttribute("size")),Fingerprint=item.GetAttribute("fingerprint")});if(disks.Items.Count==1)disks.SelectedIndex=0;computer.Text="Equipamento identificado\n"+result.GetAttribute("computer");loading=false;SetBusy(false,disks.Items.Count>0?"Tudo pronto. Escolha uma opção para começar.":"Disco interno não encontrado. A instalação tradicional permite carregar drivers.");};worker.RunWorkerAsync();
        }
        void BeginInstall(string mode) {
            if(busy)return;DiskChoice disk=disks.SelectedItem as DiskChoice;
            if(mode=="Quick"&&disk==null){MessageBox.Show(this,"Escolha o disco de destino na lista.","Selecione o disco",MessageBoxButtons.OK,MessageBoxIcon.Information);return;}
            if(mode=="Quick"&&MessageBox.Show(this,"Instalar o Windows 11 Pro neste disco?\r\n\r\n"+disk+"\r\n\r\nTodos os arquivos e partições desse disco serão apagados. O pendrive será preservado.","Confirmar instalação rápida",MessageBoxButtons.YesNo,MessageBoxIcon.Warning,MessageBoxDefaultButton.Button2)!=DialogResult.Yes)return;
            if(preview){SetBusy(true,mode=="Quick"?"Preparando a instalação rápida… (prévia visual)":"Abrindo o instalador tradicional… (prévia visual)");var t=new Timer();t.Interval=2800;t.Tick+=delegate{t.Stop();LoadPreview();t.Dispose();};t.Start();return;}
            SetBusy(true,mode=="Quick"?"Preparando a instalação rápida…":"Preparando o instalador tradicional…");
            var worker=new BackgroundWorker();worker.DoWork+=delegate(object s,DoWorkEventArgs e){e.Result=Backend("Prepare",mode,mode=="Quick"?disk:null,mediaFingerprint);};
            worker.RunWorkerCompleted+=delegate(object s,RunWorkerCompletedEventArgs e){worker.Dispose();if(e.Error!=null){Error(e.Error.Message);return;}try{
                var result=(XmlElement)e.Result;string setup=result.GetAttribute("setup");string answer=result.GetAttribute("answerFile");string source=result.GetAttribute("sourceRoot");
                if(!InWinPE()||!Path.GetFullPath(setup).StartsWith(Path.Combine(source,"Media")+"\\",StringComparison.OrdinalIgnoreCase)||!File.Exists(setup)||!File.Exists(answer))throw new InvalidOperationException("A mídia mudou. Reinicie a preparação.");
                var start=new ProcessStartInfo(setup,"/unattend:"+Quote(answer));start.UseShellExecute=false;start.CreateNoWindow=true;Process setupProcess=Process.Start(start);status.Text="Instalação iniciada. O Windows continuará automaticamente; mantenha o pendrive conectado.";SendToBack();
                var monitor=new Timer();monitor.Interval=1500;monitor.Tick+=delegate{if(setupProcess.HasExited){monitor.Stop();int code=setupProcess.ExitCode;setupProcess.Dispose();monitor.Dispose();if(code!=0){Error("O instalador retornou um erro ("+code+"). Confira as telas do Windows Setup ou tente o modo tradicional.");BringToFront();}else{status.Text="O Windows Setup assumiu a instalação. Aguarde o reinício pelo SSD.";}}};monitor.Start();
            }catch(Exception ex){Error(ex.Message);}};worker.RunWorkerAsync();
        }
    }
    internal static class Program {
        [STAThread] static void Main(string[] args) {
            bool preview=Array.IndexOf(args,"--preview")>=0,loading=Array.IndexOf(args,"--preview-loading")>=0;string render=null;
            for(int i=0;i<args.Length-1;i++)if(args[i]=="--render"){render=Path.GetFullPath(args[i+1]);preview=true;}
            Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
            try{Application.Run(new MainWindow(preview,render,loading));}catch(Exception ex){MessageBox.Show(ex.Message,"DNW - Batch Formatting",MessageBoxButtons.OK,MessageBoxIcon.Error);}
        }
    }
}
