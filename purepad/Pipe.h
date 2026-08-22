// Pipe.h: interface for the CPipe class.
//
//////////////////////////////////////////////////////////////////////

#if !defined(AFX_PIPE_H__87EB6D20_9FD1_11D2_BCEB_AE52699C7164__INCLUDED_)
#define AFX_PIPE_H__87EB6D20_9FD1_11D2_BCEB_AE52699C7164__INCLUDED_

#include "Buffer.h"	// Added by ClassView
#include "ProcessSession.h"
#include <climits>
#include <filesystem>
#include <string_view>
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

class Utf8Decoder {
public:
	CString Push(std::string_view bytes)
	{
		if (!bytes.empty())
			pending_.append(bytes.data(), bytes.size());
		return Decode(CompletePrefixSize(pending_));
	}

	CString Finish()
	{
		return Decode(pending_.size());
	}

private:
	static bool IsContinuation(unsigned char byte)
	{
		return (byte & 0xc0) == 0x80;
	}

	static size_t CompletePrefixSize(std::string_view bytes)
	{
		size_t index = 0;
		while (index < bytes.size()) {
			const unsigned char first =
				static_cast<unsigned char>(bytes[index]);
			if (first < 0x80) {
				++index;
				continue;
			}

			size_t sequence_length = 0;
			if (first >= 0xc2 && first <= 0xdf)
				sequence_length = 2;
			else if (first >= 0xe0 && first <= 0xef)
				sequence_length = 3;
			else if (first >= 0xf0 && first <= 0xf4)
				sequence_length = 4;
			else {
				++index;
				continue;
			}

			bool invalid = false;
			const size_t available = bytes.size() - index;
			for (size_t offset = 1;
				offset < sequence_length && offset < available; ++offset) {
				if (!IsContinuation(
						static_cast<unsigned char>(bytes[index + offset]))) {
					invalid = true;
					break;
				}
			}
			if (invalid) {
				++index;
				continue;
			}
			if (available < sequence_length)
				return index;

			const unsigned char second =
				static_cast<unsigned char>(bytes[index + 1]);
			if ((first == 0xe0 && second < 0xa0) ||
				(first == 0xed && second >= 0xa0) ||
				(first == 0xf0 && second < 0x90) ||
				(first == 0xf4 && second >= 0x90)) {
				++index;
				continue;
			}
			index += sequence_length;
		}
		return index;
	}

	CString Decode(size_t byte_count)
	{
		if (byte_count == 0 || byte_count > static_cast<size_t>(INT_MAX))
			return CString();
		const int source_length = static_cast<int>(byte_count);
		const int length = MultiByteToWideChar(CP_UTF8, 0, pending_.data(),
			source_length, nullptr, 0);
		if (length <= 0)
			return CString();
		CString result;
		LPTSTR output = result.GetBuffer(length);
		const int converted = MultiByteToWideChar(CP_UTF8, 0, pending_.data(),
			source_length, output, length);
		if (converted <= 0) {
			result.ReleaseBufferSetLength(0);
			return result;
		}
		result.ReleaseBufferSetLength(converted);
		pending_.erase(0, byte_count);
		return result;
	}

	std::string pending_;
};

inline BOOL AppendDecodedOutput(CBuffer& buffer, Utf8Decoder& decoder,
	std::string_view bytes)
{
	const CString text = decoder.Push(bytes);
	return buffer.Write(text.GetString(), text.GetLength());
}

inline BOOL FlushDecodedOutput(CBuffer& buffer, Utf8Decoder& decoder)
{
	const CString text = decoder.Finish();
	return buffer.Write(text.GetString(), text.GetLength());
}

inline ProcessLaunch BuildPipeLaunch(std::wstring application,
	std::vector<std::wstring> arguments, const std::wstring& script,
	std::wstring prompt)
{
	ProcessLaunch launch;
	launch.application = std::move(application);
	launch.arguments = std::move(arguments);
	launch.prompt = std::move(prompt);

	const std::filesystem::path script_path(script);
	launch.working_directory = script_path.parent_path().native();
	if (!launch.working_directory.empty() &&
		launch.working_directory.back() == L':' &&
		script.size() > launch.working_directory.size()) {
		const wchar_t separator = script[launch.working_directory.size()];
		if (separator == L'\\' || separator == L'/')
			launch.working_directory.push_back(separator);
	}
	const std::wstring basename = script_path.filename().native();
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
