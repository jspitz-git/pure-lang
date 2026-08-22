// Pipe.cpp: implementation of the CPipe class.
//
//////////////////////////////////////////////////////////////////////

#include "stdafx.h"
#include "qpad.h"
#include "Pipe.h"
#include "MainFrm.h"

#include <string>
#include <string_view>
#include <vector>

#ifdef _DEBUG
#undef THIS_FILE
static char THIS_FILE[]=__FILE__;
#define new DEBUG_NEW
#endif

namespace {

std::wstring WideString(LPCTSTR value)
{
	if (!value)
		return {};
	return std::wstring(value, _tcslen(value));
}

std::vector<std::wstring> SplitArguments(LPCTSTR value)
{
	std::vector<std::wstring> result;
	CString arguments(value ? value : _T(""));
	int position = 0;
	for (CString token = arguments.Tokenize(_T(" \t"), position);
		!token.IsEmpty();
		token = arguments.Tokenize(_T(" \t"), position)) {
		result.emplace_back(static_cast<LPCTSTR>(token), token.GetLength());
	}
	return result;
}

CString Utf8Text(std::string_view bytes)
{
	if (bytes.empty())
		return CString();
	const int length = MultiByteToWideChar(CP_UTF8, 0, bytes.data(),
		static_cast<int>(bytes.size()), nullptr, 0);
	if (length <= 0)
		return CString();
	CString result;
	LPTSTR buffer = result.GetBuffer(length);
	const int converted = MultiByteToWideChar(CP_UTF8, 0, bytes.data(),
		static_cast<int>(bytes.size()), buffer, length);
	result.ReleaseBuffer(converted > 0 ? converted : 0);
	return result;
}

std::string Utf8Bytes(LPCTSTR value)
{
	if (!value || !*value)
		return {};
	const int source_length = static_cast<int>(_tcslen(value));
	const int length = WideCharToMultiByte(CP_UTF8, 0, value, source_length,
		nullptr, 0, nullptr, nullptr);
	if (length <= 0)
		return {};
	std::string result(static_cast<size_t>(length), '\0');
	const int converted = WideCharToMultiByte(CP_UTF8, 0, value,
		source_length, result.data(), length, nullptr, nullptr);
	if (converted <= 0)
		return {};
	return result;
}

CString Win32ErrorText(DWORD error)
{
	LPWSTR allocated = nullptr;
	const DWORD length = FormatMessageW(
		FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM |
			FORMAT_MESSAGE_IGNORE_INSERTS,
		nullptr, error, MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
		reinterpret_cast<LPWSTR>(&allocated), 0, nullptr);
	CString result;
	if (length != 0 && allocated != nullptr) {
		result.SetString(allocated, static_cast<int>(length));
		result.TrimRight(_T("\r\n"));
	}
	LocalFree(allocated);
	return result;
}

} // namespace

//////////////////////////////////////////////////////////////////////
// Construction/Destruction
//////////////////////////////////////////////////////////////////////

CPipe::CPipe()
{
}

CPipe::~CPipe()
{
	Kill();
}

// public member functions

BOOL CPipe::Run(LPCTSTR name, LPCTSTR pname)
{
	return Run2(CMainFrame::m_strPurePath, _T("-i -q"), name, pname);
}

BOOL CPipe::Debug(LPCTSTR name, LPCTSTR pname)
{
	return Run2(CMainFrame::m_strPurePath, _T("-i -q -g"), name, pname);
}

void CPipe::Write(LPCTSTR lpszBuf)
{
	const std::string bytes = Utf8Bytes(lpszBuf);
	if (!bytes.empty())
		m_session.Write(bytes);
}

CString CPipe::Read()
{
	return m_bufInput.Read();
}

CString CPipe::Peek()
{
	return m_bufInput.Peek();
}

void CPipe::Empty()
{
	m_bufInput.Empty();
}

int CPipe::GetLength()
{
	return m_bufInput.GetLength();
}

BOOL CPipe::IsEmpty()
{
	return m_bufInput.IsEmpty();
}

BOOL CPipe::Run2(LPCTSTR application, LPCTSTR arguments,
	LPCTSTR name, LPCTSTR display_name)
{
	Kill();
	CWnd* main_window = AfxGetMainWnd();
	const HWND window = main_window ? main_window->GetSafeHwnd() : nullptr;

	if (!CMainFrame::m_bLogReset) {
		CString message;
		message.Format(_T("// %s\r\n"), display_name ? display_name : _T(""));
		m_bufInput.Write(message);
		if (window)
			::PostMessage(window, WM_USER_INPUT, 0, 0);
	}

	auto launch = purepad::detail::BuildPipeLaunch(
		WideString(application), SplitArguments(arguments), WideString(name),
		WideString(CMainFrame::m_strQPS));
	purepad::ProcessCallbacks callbacks;
	callbacks.output = [this, window](std::string_view bytes) {
		const CString text = Utf8Text(bytes);
		if (!text.IsEmpty() && m_bufInput.Write(text) && window)
			::PostMessage(window, WM_USER_INPUT, 0, 0);
	};
	callbacks.exited = [this] {
		m_session.Stop();
	};

	const purepad::ProcessResult result =
		m_session.Start(launch, std::move(callbacks));
	if (result.ok())
		return TRUE;

	CString error = Win32ErrorText(result.win32_error);
	if (error.IsEmpty())
		error.Format(_T("Windows error %lu"), result.win32_error);
	CString message;
	message.Format(_T("Unable to start Pure interpreter:\n%s\n\n%s"),
		application ? application : _T(""), static_cast<LPCTSTR>(error));
	AfxMessageBox(message, MB_OK | MB_ICONERROR);
	return FALSE;
}

void CPipe::Break()
{
	m_session.Break();
}

void CPipe::Kill()
{
	m_session.Stop();
}

BOOL CPipe::IsRunning()
{
	return m_session.IsRunning() ? TRUE : FALSE;
}
