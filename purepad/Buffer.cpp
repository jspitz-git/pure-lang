// Buffer.cpp: implementation of the CBuffer class.
//
//////////////////////////////////////////////////////////////////////

#include "stdafx.h"
#include "qpad.h"
#include "Buffer.h"

#include <cstring>

#ifdef _DEBUG
#undef THIS_FILE
static char THIS_FILE[]=__FILE__;
#define new DEBUG_NEW
#endif

namespace {

CString NormalizeLineEnds(const CString& value)
{
	CString result;
	LPTSTR output = result.GetBuffer(value.GetLength() * 2);
	int output_length = 0;
	for (int index = 0; index < value.GetLength(); ++index) {
		const TCHAR character = value[index];
		if (character == _T('\r') && index + 1 < value.GetLength() &&
			value[index + 1] == _T('\n')) {
			output[output_length++] = _T('\r');
			output[output_length++] = _T('\n');
			++index;
		} else if (character == _T('\n')) {
			output[output_length++] = _T('\r');
			output[output_length++] = _T('\n');
		} else {
			output[output_length++] = character;
		}
	}
	result.ReleaseBufferSetLength(output_length);
	return result;
}

} // namespace

//////////////////////////////////////////////////////////////////////
// Construction/Destruction
//////////////////////////////////////////////////////////////////////

CBuffer::CBuffer()
{
}

CBuffer::~CBuffer()
{
}

BOOL CBuffer::Write(LPCTSTR lpszStr)
{
	return Write(lpszStr, lpszStr ? static_cast<int>(_tcslen(lpszStr)) : 0);
}

BOOL CBuffer::Write(LPCTSTR lpszStr, int length)
{
	if (!lpszStr || length <= 0) return FALSE;
	CSingleLock sLock(&m_mutex);
	sLock.Lock();
	BOOL res = m_strBuf.IsEmpty();
	const int old_length = m_strBuf.GetLength();
	LPTSTR buffer = m_strBuf.GetBuffer(old_length + length);
	std::memcpy(buffer + old_length, lpszStr,
		static_cast<size_t>(length) * sizeof(TCHAR));
	m_strBuf.ReleaseBufferSetLength(old_length + length);
	sLock.Unlock();
	return res;
}

CString CBuffer::Read()
{
	CSingleLock sLock(&m_mutex, TRUE);
	CString strBuf = NormalizeLineEnds(m_strBuf);
	m_strBuf.Empty();
	return strBuf;
}

CString CBuffer::Peek()
{
	CSingleLock sLock(&m_mutex, TRUE);
	return NormalizeLineEnds(m_strBuf);
}

void CBuffer::Empty()
{
	CSingleLock sLock(&m_mutex);
	sLock.Lock();
	m_strBuf.Empty();
	sLock.Unlock();
}

int CBuffer::GetLength()
{
	CSingleLock sLock(&m_mutex);
	sLock.Lock();
	int len = m_strBuf.GetLength();
	sLock.Unlock();
	return len;
}

BOOL CBuffer::IsEmpty()
{
	CSingleLock sLock(&m_mutex);
	sLock.Lock();
	BOOL bIsEmpty = m_strBuf.IsEmpty();
	sLock.Unlock();
	return bIsEmpty;
}
