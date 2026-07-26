// qpad.cpp : Defines the class behaviors for the application.
//

#include "stdafx.h"
#include "qpad.h"
#include "pipe.h"

#include "MainFrm.h"
#include "qpadDoc.h"

#include <ShlObj.h>
#include <vector>

#ifdef _DEBUG
#define new DEBUG_NEW
#undef THIS_FILE
static char THIS_FILE[] = __FILE__;
#endif

/////////////////////////////////////////////////////////////////////////////
// CQpadApp

BEGIN_MESSAGE_MAP(CQpadApp, CWinApp)
	//{{AFX_MSG_MAP(CQpadApp)
	ON_COMMAND(ID_APP_ABOUT, OnAppAbout)
	ON_COMMAND(ID_HELP_FINDER, OnHelpFinder)
	//}}AFX_MSG_MAP
	// Standard file based document commands
	ON_COMMAND(ID_FILE_NEW, CWinApp::OnFileNew)
	ON_COMMAND(ID_FILE_OPEN, CWinApp::OnFileOpen)
	// Standard print setup command
	ON_COMMAND(ID_FILE_PRINT_SETUP, CWinApp::OnFilePrintSetup)
END_MESSAGE_MAP()

/////////////////////////////////////////////////////////////////////////////
// CQpadApp construction

CQpadApp::CQpadApp()
{
	// TODO: add construction code here,
	// Place all significant initialization in InitInstance
}

/////////////////////////////////////////////////////////////////////////////
// The one and only CQpadApp object

CQpadApp theApp;

static CString Environment(LPCTSTR name)
{
	DWORD required = GetEnvironmentVariable(name, NULL, 0);
	if (!required)
		return CString();
	CString value;
	LPTSTR buffer = value.GetBuffer(static_cast<int>(required));
	DWORD copied = GetEnvironmentVariable(name, buffer, required);
	if (!copied || copied >= required) {
		value.ReleaseBuffer(0);
		return CString();
	}
	value.ReleaseBuffer(static_cast<int>(copied));
	return value;
}

static BOOL PrepareUnicodeProfile(LPCTSTR name, BOOL& fresh)
{
	WIN32_FILE_ATTRIBUTE_DATA info;
	fresh = !GetFileAttributesEx(name, GetFileExInfoStandard, &info) ||
		(info.nFileSizeHigh == 0 && info.nFileSizeLow == 0);
	if (!fresh)
		return TRUE;
	HANDLE file = CreateFile(name, GENERIC_WRITE, FILE_SHARE_READ, NULL,
		CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
	if (file == INVALID_HANDLE_VALUE)
		return FALSE;
	const WCHAR bom = 0xfeff;
	DWORD written = 0;
	BOOL result = WriteFile(file, &bom, sizeof(bom), &written, NULL) &&
		written == sizeof(bom);
	CloseHandle(file);
	return result;
}

static void MigrateLegacyProfile(LPCTSTR profileName)
{
	HKEY appKey;
	if (RegOpenKeyEx(HKEY_CURRENT_USER,
		_T("Software\\Pure Software\\PurePad"), 0, KEY_READ,
		&appKey) != ERROR_SUCCESS)
		return;

	DWORD sectionCount = 0, maxSectionLength = 0;
	if (RegQueryInfoKey(appKey, NULL, NULL, NULL, &sectionCount,
		&maxSectionLength, NULL, NULL, NULL, NULL, NULL, NULL) !=
		ERROR_SUCCESS) {
		RegCloseKey(appKey);
		return;
	}
	std::vector<TCHAR> section(maxSectionLength + 1);
	for (DWORD sectionIndex = 0; sectionIndex < sectionCount;
		++sectionIndex) {
		DWORD sectionLength = static_cast<DWORD>(section.size());
		if (RegEnumKeyEx(appKey, sectionIndex, section.data(),
			&sectionLength, NULL, NULL, NULL, NULL) != ERROR_SUCCESS)
			continue;
		HKEY sectionKey;
		if (RegOpenKeyEx(appKey, section.data(), 0, KEY_READ,
			&sectionKey) != ERROR_SUCCESS)
			continue;

		DWORD valueCount = 0, maxNameLength = 0, maxDataLength = 0;
		if (RegQueryInfoKey(sectionKey, NULL, NULL, NULL, NULL, NULL,
			NULL, &valueCount, &maxNameLength, &maxDataLength, NULL,
			NULL) == ERROR_SUCCESS) {
			std::vector<TCHAR> valueName(maxNameLength + 1);
			std::vector<TCHAR> data(
				(maxDataLength + sizeof(TCHAR) - 1) / sizeof(TCHAR) + 1);
			for (DWORD valueIndex = 0; valueIndex < valueCount;
				++valueIndex) {
				DWORD nameLength = static_cast<DWORD>(valueName.size());
				DWORD dataLength = static_cast<DWORD>(
					data.size() * sizeof(TCHAR));
				DWORD type = REG_NONE;
				if (RegEnumValue(sectionKey, valueIndex,
					valueName.data(), &nameLength, NULL, &type,
					reinterpret_cast<LPBYTE>(data.data()), &dataLength) !=
					ERROR_SUCCESS)
					continue;
				CString value;
				if (type == REG_DWORD && dataLength == sizeof(DWORD)) {
					DWORD number;
					memcpy(&number, data.data(), sizeof(number));
					value.Format(_T("%d"), static_cast<LONG>(number));
				} else if (type == REG_SZ || type == REG_EXPAND_SZ) {
					data[dataLength / sizeof(TCHAR)] = 0;
					value = data.data();
				} else {
					continue;
				}
				WritePrivateProfileString(section.data(), valueName.data(),
					value, profileName);
			}
		}
		RegCloseKey(sectionKey);
	}
	RegCloseKey(appKey);
	WritePrivateProfileString(NULL, NULL, NULL, profileName);
}

static BOOL ConfigureUserData(CQpadApp& app)
{
	CString dataPath = Environment(_T("PUREPAD_USER_DATA"));
	if (dataPath.IsEmpty()) {
		PWSTR roamingPath = NULL;
		HRESULT result = SHGetKnownFolderPath(FOLDERID_RoamingAppData,
			KF_FLAG_CREATE, NULL, &roamingPath);
		if (FAILED(result))
			return FALSE;
		dataPath = roamingPath;
		CoTaskMemFree(roamingPath);
		dataPath += _T("\\Pure\\PurePad");
	}
	int createResult = SHCreateDirectoryEx(NULL, dataPath, NULL);
	if (createResult != ERROR_SUCCESS &&
		createResult != ERROR_ALREADY_EXISTS &&
		createResult != ERROR_FILE_EXISTS)
		return FALSE;

	CString profileName = dataPath + _T("\\PurePad.ini");
	BOOL fresh = FALSE;
	if (!PrepareUnicodeProfile(profileName, fresh))
		return FALSE;
	if (fresh)
		MigrateLegacyProfile(profileName);

	BOOL tracking = AfxEnableMemoryTracking(FALSE);
	free((void*)app.m_pszProfileName);
	app.m_pszProfileName = _tcsdup(profileName);
	AfxEnableMemoryTracking(tracking);
	if (!app.m_pszProfileName)
		return FALSE;
	app.m_strUserDataPath = dataPath;
	return TRUE;
}

/////////////////////////////////////////////////////////////////////////////
// CQpadApp initialization

BOOL CQpadApp::InitInstance()
{
	AfxEnableControlContainer();

	// Standard initialization
	// If you are not using these features and wish to reduce the size
	//  of your final executable, you should remove from the following
	//  the specific initialization routines you do not need.

	if (!ConfigureUserData(*this)) {
		AfxMessageBox(_T("Unable to initialize the PurePad user data directory."),
			MB_OK | MB_ICONERROR);
		return FALSE;
	}
	// Load settings from the per-user AppData profile.

	LoadStdProfileSettings(8);  // Load standard INI file options (including MRU)
	CMainFrame::Initialize();

	// Register the application's document templates.  Document templates
	//  serve as the connection between documents, frame windows and views.

	CSingleDocTemplate* pDocTemplate;
	pDocTemplate = new CSingleDocTemplate(
		IDR_MAINFRAME,
		RUNTIME_CLASS(CQpadDoc),
		RUNTIME_CLASS(CMainFrame),       // main SDI frame window
		RUNTIME_CLASS(CEvalView));
	AddDocTemplate(pDocTemplate);

	// Enable DDE Execute open
	EnableShellOpen();
	RegisterShellFileTypes(TRUE);

	// Parse command line for standard shell commands, DDE, file open
	CCommandLineInfo cmdInfo;
	ParseCommandLine(cmdInfo);

	// Dispatch commands specified on the command line
	if (!ProcessShellCommand(cmdInfo))
		return FALSE;

	// The one and only window has been initialized, so show and update it.
//	m_pMainWnd->ShowWindow(SW_SHOW);
	((CMainFrame*)m_pMainWnd)->InitialShowWindow(SW_SHOW);
	m_pMainWnd->UpdateWindow();

	// Enable drag/drop open
	m_pMainWnd->DragAcceptFiles();

	return TRUE;
}

int CQpadApp::ExitInstance() 
{
	CMainFrame::Terminate();	
	return CWinApp::ExitInstance();
}

/////////////////////////////////////////////////////////////////////////////
// CAboutDlg dialog used for App About

class CAboutDlg : public CDialog
{
public:
	CAboutDlg();

// Dialog Data
	//{{AFX_DATA(CAboutDlg)
	enum { IDD = IDD_ABOUTBOX };
	//}}AFX_DATA

	// ClassWizard generated virtual function overrides
	//{{AFX_VIRTUAL(CAboutDlg)
	protected:
	virtual void DoDataExchange(CDataExchange* pDX);    // DDX/DDV support
	//}}AFX_VIRTUAL

// Implementation
protected:
	//{{AFX_MSG(CAboutDlg)
		// No message handlers
	//}}AFX_MSG
	DECLARE_MESSAGE_MAP()
};

CAboutDlg::CAboutDlg() : CDialog(CAboutDlg::IDD)
{
	//{{AFX_DATA_INIT(CAboutDlg)
	//}}AFX_DATA_INIT
}

void CAboutDlg::DoDataExchange(CDataExchange* pDX)
{
	CDialog::DoDataExchange(pDX);
	//{{AFX_DATA_MAP(CAboutDlg)
	//}}AFX_DATA_MAP
}

BEGIN_MESSAGE_MAP(CAboutDlg, CDialog)
	//{{AFX_MSG_MAP(CAboutDlg)
		// No message handlers
	//}}AFX_MSG_MAP
END_MESSAGE_MAP()

// App command to run the dialog
void CQpadApp::OnAppAbout()
{
	CAboutDlg aboutDlg;
	aboutDlg.DoModal();
}

void CQpadApp::OnHelpFinder() 
{
	::HtmlHelp(NULL, CMainFrame::m_strAppPath+_T("\\puredoc.chm"),
		HH_DISPLAY_TOPIC, 0);	
}

/////////////////////////////////////////////////////////////////////////////
// CQpadApp message handlers

BOOL CQpadApp::OnIdle(LONG lCount) 
{
	CMainFrame* pFrame = (CMainFrame*) AfxGetMainWnd();
	CStatusBar* pStatusBar = (CStatusBar*) pFrame->GetDescendantWindow(AFX_IDW_STATUS_BAR);

	if(pStatusBar)
	{
		CEdit &edit = ((CEditView*)pFrame->GetActiveView())->GetEditCtrl();
		CString s1;
		UINT i = edit.LineFromChar();
		CString ind;
		ind.LoadString(ID_INDICATOR_LINE);
		int p = ind.Find(' ');
		s1.Format(_T("%s %u"), ind.Left(p), ++i);
		pStatusBar->SetPaneText(pStatusBar->CommandToIndex(ID_INDICATOR_LINE), s1);
	}

	pFrame->UpdateTitle();

	return CWinApp::OnIdle(lCount);
}

