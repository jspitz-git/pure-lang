// qpadDoc.cpp : implementation of the CQpadDoc class
//

#include "stdafx.h"
#include "qpad.h"
#include "pipe.h"

#include "qpadDoc.h"
#include "MainFrm.h"

#include <vector>

#ifdef _DEBUG
#define new DEBUG_NEW
#undef THIS_FILE
static char THIS_FILE[] = __FILE__;
#endif

/////////////////////////////////////////////////////////////////////////////
// CQpadDoc

IMPLEMENT_DYNCREATE(CQpadDoc, CDocument)

BEGIN_MESSAGE_MAP(CQpadDoc, CDocument)
	//{{AFX_MSG_MAP(CQpadDoc)
	//}}AFX_MSG_MAP
END_MESSAGE_MAP()

/////////////////////////////////////////////////////////////////////////////
// CQpadDoc construction/destruction

CQpadDoc::CQpadDoc()
{
}

CQpadDoc::~CQpadDoc()
{
}

BOOL CQpadDoc::OnNewDocument()
{
	if (!CDocument::OnNewDocument())
		return FALSE;

	((CEditView*)m_viewList.GetHead())->SetWindowText(NULL);

	return TRUE;
}



/////////////////////////////////////////////////////////////////////////////
// CQpadDoc serialization

static BOOL DecodeText(const BYTE* bytes, int length, CString& text)
{
	if (!length) {
		text.Empty();
		return TRUE;
	}
	if (length >= 2 && bytes[0] == 0xff && bytes[1] == 0xfe) {
		int byteLength = length - 2;
		if (byteLength % sizeof(WCHAR))
			return FALSE;
		int charCount = byteLength / sizeof(WCHAR);
		LPWSTR output = text.GetBuffer(charCount);
		memcpy(output, bytes + 2, byteLength);
		text.ReleaseBuffer(charCount);
		return TRUE;
	}
	if (length >= 2 && bytes[0] == 0xfe && bytes[1] == 0xff) {
		int byteLength = length - 2;
		if (byteLength % sizeof(WCHAR))
			return FALSE;
		int charCount = byteLength / sizeof(WCHAR);
		LPWSTR output = text.GetBuffer(charCount);
		for (int i = 0; i < charCount; ++i)
			output[i] = static_cast<WCHAR>(
				(bytes[2 + 2*i] << 8) | bytes[3 + 2*i]);
		text.ReleaseBuffer(charCount);
		return TRUE;
	}

	int offset = length >= 3 && bytes[0] == 0xef && bytes[1] == 0xbb &&
		bytes[2] == 0xbf ? 3 : 0;
	LPCCH input = reinterpret_cast<LPCCH>(bytes + offset);
	int inputLength = length - offset;
	UINT codePage = CP_UTF8;
	DWORD flags = MB_ERR_INVALID_CHARS;
	int charCount = MultiByteToWideChar(codePage, flags, input,
		inputLength, NULL, 0);
	if (!charCount && inputLength) {
		codePage = CP_ACP;
		flags = 0;
		charCount = MultiByteToWideChar(codePage, flags, input,
			inputLength, NULL, 0);
	}
	if (!charCount && inputLength)
		return FALSE;
	LPWSTR output = text.GetBuffer(charCount);
	MultiByteToWideChar(codePage, flags, input, inputLength, output, charCount);
	text.ReleaseBuffer(charCount);
	return TRUE;
}

void CQpadDoc::Serialize(CArchive& ar)
{
	CEditView* view = static_cast<CEditView*>(m_viewList.GetHead());
	if (ar.IsStoring()) {
		CString text;
		view->GetWindowText(text);
		int byteCount = WideCharToMultiByte(CP_UTF8, 0, text,
			text.GetLength(), NULL, 0, NULL, NULL);
		std::vector<char> bytes(byteCount);
		if (byteCount) {
			WideCharToMultiByte(CP_UTF8, 0, text, text.GetLength(),
				bytes.data(), byteCount, NULL, NULL);
			ar.Write(bytes.data(), byteCount);
		}
	} else {
		ULONGLONG fileLength = ar.GetFile()->GetLength();
		if (fileLength > view->GetEditCtrl().GetLimitText() * 4ULL) {
			AfxMessageBox(AFX_IDP_FILE_TOO_LARGE);
			AfxThrowUserException();
		}
		std::vector<BYTE> bytes(static_cast<size_t>(fileLength));
		if (fileLength)
			ar.Read(bytes.data(), static_cast<UINT>(fileLength));
		CString text;
		if (!DecodeText(bytes.data(), static_cast<int>(fileLength), text)) {
			AfxMessageBox(_T("Unable to decode the document text."),
				MB_OK | MB_ICONERROR);
			AfxThrowUserException();
		}
		if (static_cast<UINT>(text.GetLength()) >
			view->GetEditCtrl().GetLimitText()) {
			AfxMessageBox(AFX_IDP_FILE_TOO_LARGE);
			AfxThrowUserException();
		}
		view->SetWindowText(text);
	}
}

/////////////////////////////////////////////////////////////////////////////
// CQpadDoc diagnostics

#ifdef _DEBUG
void CQpadDoc::AssertValid() const
{
	CDocument::AssertValid();
}

void CQpadDoc::Dump(CDumpContext& dc) const
{
	CDocument::Dump(dc);
}
#endif //_DEBUG

/////////////////////////////////////////////////////////////////////////////
// CQpadDoc commands



BOOL CQpadDoc::OnOpenDocument(LPCTSTR lpszPathName) 
{
	if (!CDocument::OnOpenDocument(lpszPathName))
		return FALSE;
	CEditView* edit = ((CEditView*)m_viewList.GetHead());

	CString s;
	edit->GetWindowText(s);
	int n = s.Find(_T('\r'));
	if (n < 0) {
		// Not a single CR in this file, probably a UNIX file (LF endings).
		s.Replace(_T("\n"), _T("\r\n"));
		edit->SetWindowText(s);
	}

	// TODO: Speziellen Erstellungscode hier einfügen
	
	return TRUE;
}
