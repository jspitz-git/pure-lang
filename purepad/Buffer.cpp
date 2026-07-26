// Buffer.cpp: implementation of the CBuffer class.
//
//////////////////////////////////////////////////////////////////////

#include "stdafx.h"
#include "qpad.h"
#include "Buffer.h"

#ifdef _DEBUG
#undef THIS_FILE
static char THIS_FILE[]=__FILE__;
#define new DEBUG_NEW
#endif

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
	if (!lpszStr || !*lpszStr) return FALSE;
	CSingleLock sLock(&m_mutex);
	sLock.Lock();
	BOOL res = m_strBuf.IsEmpty();
	m_strBuf += lpszStr;
	sLock.Unlock();
	return res;
}

CString CBuffer::Read()
{
	CSingleLock sLock(&m_mutex, TRUE);
	CString strBuf = m_strBuf;
	// normalize line ends
	strBuf.Replace(_T("\r\n"), _T("\n"));
	strBuf.Replace(_T("\n"), _T("\r\n"));
	m_strBuf.Empty();
	return strBuf;
}

CString CBuffer::Peek()
{
	CSingleLock sLock(&m_mutex, TRUE);
	CString strBuf = m_strBuf;
	strBuf.Replace(_T("\r\n"), _T("\n"));
	strBuf.Replace(_T("\n"), _T("\r\n"));
	return strBuf;
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
