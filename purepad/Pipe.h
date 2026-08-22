// Pipe.h: interface for the CPipe class.
//
//////////////////////////////////////////////////////////////////////

#if !defined(AFX_PIPE_H__87EB6D20_9FD1_11D2_BCEB_AE52699C7164__INCLUDED_)
#define AFX_PIPE_H__87EB6D20_9FD1_11D2_BCEB_AE52699C7164__INCLUDED_

#include "Buffer.h"	// Added by ClassView
#include "ProcessSession.h"
#include <utility>
#if _MSC_VER > 1000
#pragma once
#endif // _MSC_VER > 1000

/*
  The CPipe class implements a bidirectional pipe to an interpreter
  child process. The member functions allow to create a new child
  process, signal it a break, stop the process, feed input into the
  child's stdin, and obtain its response on the child's stdout. Only
  a single child process can be active at any time. The application
  is notified when new input from the interpreter's stdout becomes
  available by means of the WM_USER_INPUT message, which is passed
  to the main window. Furthermore, the main window is notfied by
  a WM_USER_COMPILE message when the compiler has finished, giving
  its result in the LPARAM parameter.
*/

namespace purepad {
namespace detail {

inline ProcessLaunch BuildPipeLaunch(std::wstring application,
	std::vector<std::wstring> arguments, const std::wstring& script,
	std::wstring prompt)
{
	ProcessLaunch launch;
	launch.application = std::move(application);
	launch.arguments = std::move(arguments);
	launch.prompt = std::move(prompt);

	const size_t slash = script.find_last_of(L"/\\");
	if (slash == std::wstring::npos) {
		if (!script.empty())
			launch.arguments.push_back(script);
		return launch;
	}

	const size_t directory_length =
		slash == 2 && script.size() > 2 && script[1] == L':' ? 3 : slash;
	launch.working_directory = script.substr(0, directory_length);
	const std::wstring basename = script.substr(slash + 1);
	if (!basename.empty())
		launch.arguments.push_back(basename);
	return launch;
}

} // namespace detail
} // namespace purepad

class CPipe  
{
public:

	// construction

	CPipe();
	virtual ~CPipe();

	BOOL Run(LPCTSTR name, LPCTSTR pname);
	// create a new interpreter process for script name (full path
	// or empty string if none) kill off an existing child process
	// if present; returns TRUE iff interpreter was started
	// successfully

	BOOL Debug(LPCTSTR name, LPCTSTR pname);
	// same as Run(), but invokes the debugger

	void Break();
	// signal a break (Ctl-C)

	void Kill();
	// kill the child process (called automatically when the instance
	// is destroyed); also removes the code file

	BOOL IsRunning();
	// checks whether the child process is still up and running

	void Write(LPCTSTR lpszBuf);
	// send a string to the child's stdin

	CString Read();
	// get the currently available output from the child's stdout
	// and empty the buffer

	CString Peek();
	// like Read(), but does not empty the buffer

	void Empty();
	// empty the input buffer

	int GetLength();
	// get the current length of the input buffer

	BOOL IsEmpty();
	// check whether the input buffer is empty

private:
	BOOL Run2(LPCTSTR application, LPCTSTR arguments,
		LPCTSTR name, LPCTSTR display_name);
	purepad::ProcessSession m_session;
	CBuffer m_bufInput;
	CBuffer m_bufOutput;
};

#endif // !defined(AFX_PIPE_H__87EB6D20_9FD1_11D2_BCEB_AE52699C7164__INCLUDED_)
