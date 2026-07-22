//
//	Copyright (C) 2013 Hong Jen Yee (PCMan) <pcman.tw@gmail.com>
//
//	This library is free software; you can redistribute it and/or
//	modify it under the terms of the GNU Library General Public
//	License as published by the Free Software Foundation; either
//	version 2 of the License, or (at your option) any later version.
//
//	This library is distributed in the hope that it will be useful,
//	but WITHOUT ANY WARRANTY; without even the implied warranty of
//	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
//	Library General Public License for more details.
//
//	You should have received a copy of the GNU Library General Public
//	License along with this library; if not, write to the
//	Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
//	Boston, MA  02110-1301, USA.
//

#include "PIMETextService.h"
#include <assert.h>
#include <string>
#include <libIME2/src/ComPtr.h>
#include <libIME2/src/Utils.h>
#include <libIME2/src/LangBarButton.h>
#include "PIMEImeModule.h"
#include "PIMEUiPolicy.h"
#include "resource.h"
#include <Shellapi.h>
#include <sys/stat.h>

using namespace std;

namespace PIME {

namespace {

void movePopupNearSelection(HWND hwnd, const RECT& selection) {
	if (!hwnd) {
		return;
	}
	RECT windowRect = { 0 };
	::GetWindowRect(hwnd, &windowRect);
	SIZE size = {
		windowRect.right > windowRect.left ? windowRect.right - windowRect.left : 0,
		windowRect.bottom > windowRect.top ? windowRect.bottom - windowRect.top : 0
	};
	MONITORINFO monitorInfo = { sizeof(monitorInfo) };
	HMONITOR monitor = ::MonitorFromRect(&selection, MONITOR_DEFAULTTONEAREST);
	if (!monitor || !::GetMonitorInfoW(monitor, &monitorInfo)) {
		return;
	}
	const POINT point = popupAnchorInWorkArea(selection, size, monitorInfo.rcWork);
	::SetWindowPos(hwnd, HWND_TOPMOST, point.x, point.y, 0, 0,
		SWP_NOACTIVATE | SWP_NOSIZE);
}

} // namespace

TextService::TextService(ImeModule* module):
	Ime::TextService(module),
	client_(nullptr),
	messageWindow_(nullptr),
	messageTimerId_(0),
	validCandidateListElementId_(false),
	candidateListElementId_(0),
	candidateWindow_(nullptr),
	showingCandidates_(false),
	updateFont_(false),
	candPerRow_(10),
	selKeys_(L"1234567890"),
	candUseCursor_(true),
	candFontSize_(kDefaultCandidateFontSize) {

	// font for candidate and mesasge windows
	font_ = (HFONT)GetStockObject(DEFAULT_GUI_FONT);
	LOGFONT lf;
	GetObject(font_, sizeof(lf), &lf);
	lf.lfHeight = candFontHeight();
	lf.lfWeight = FW_NORMAL;
	font_ = CreateFontIndirect(&lf);
}

TextService::~TextService(void) {
	if (client_) {
		closeClient();
	}

	if(popupMenu_)
		::DestroyMenu(popupMenu_);

	if (candidateWindow_) {
		hideCandidates();
	}

	destroyMessageWindow();

	if(font_)
		::DeleteObject(font_);
}

// virtual
void TextService::onActivate() {
	// Since we support multiple language profiles in this text service,
	// we do nothing when the whole text service is activated.
	// Instead, we do the actual initilization for each language profile when it is activated.
	// In PIME, we create different client connections for different language profiles.
}

// virtual
void TextService::onDeactivate() {
	if(client_) {
		closeClient();
	}
}

// virtual
void TextService::onFocus() {
}

// virtual
bool TextService::filterKeyDown(Ime::KeyEvent& keyEvent) {
	// if (keyEvent.isKeyToggled(VK_CAPITAL))
	//	return true;
	if(!client_)
		return false;
	return client_->filterKeyDown(keyEvent);
}

// virtual
bool TextService::onKeyDown(Ime::KeyEvent& keyEvent, Ime::EditSession* session) {
	//if (keyEvent.isKeyToggled(VK_CAPITAL))
	//	return true;
	if (!client_)
		return false;
	return client_->onKeyDown(keyEvent, session);
}

// virtual
bool TextService::filterKeyUp(Ime::KeyEvent& keyEvent) {
	if(!client_)
		return false;
	return client_->filterKeyUp(keyEvent);
}

// virtual
bool TextService::onKeyUp(Ime::KeyEvent& keyEvent, Ime::EditSession* session) {
	if(!client_)
		return false;
	return client_->onKeyUp(keyEvent, session);
}

// virtual
bool TextService::onPreservedKey(const GUID& guid) {
	if(!client_)
		return false;
	// some preserved keys registered in ctor are pressed
	return client_->onPreservedKey(guid);
}


// virtual
bool TextService::onCommand(UINT id, CommandType type) {
	if(!client_)
		return false;
	return client_->onCommand(id, type);
}

// virtual
bool TextService::onCandidateSelected(int index) {
	if(!client_)
		return false;
	auto context = currentContext();
	if(!context)
		return false;

	bool handled = false;
	HRESULT sessionResult;
	auto session = Ime::ComPtr<Ime::EditSession>::make(
		context,
		[&](Ime::EditSession* session, TfEditCookie cookie) {
			handled = client_->selectCandidate(index, session);
		}
	);
	context->RequestEditSession(clientId(), session, TF_ES_SYNC|TF_ES_READWRITE, &sessionResult);
	return handled;
}


// called when a language bar button needs a menu
// virtual
bool TextService::onMenu(LangBarButton* btn, ITfMenu* pMenu) {
	if (client_ != nullptr) {
		return client_->onMenu(btn, pMenu);
	}
	return false;
}

// called when a language bar button needs a menu
// virtual
HMENU TextService::onMenu(LangBarButton* btn) {
	if (client_ != nullptr) {
		return client_->onMenu(btn);
	}
	return NULL;
}


// virtual
void TextService::onCompartmentChanged(const GUID& key) {
	Ime::TextService::onCompartmentChanged(key);
	if(client_)
		client_->onCompartmentChanged(key);
}

// called when the keyboard is opened or closed
// virtual
void TextService::onKeyboardStatusChanged(bool opened) {
	Ime::TextService::onKeyboardStatusChanged(opened);
	if(client_)
		client_->onKeyboardStatusChanged(opened);
	if(opened) { // keyboard is opened
	}
	else { // keyboard is closed
		if(isComposing()) {
			// end current composition if needed
			if(auto context = currentContext()) {
				endComposition(context);
			}
		}
		if(showingCandidates()) // disable candidate window if it's opened
			hideCandidates();
		hideMessage(); // hide message window, if there's any
	}
}

// called just before current composition is terminated for doing cleanup.
// if forced is true, the composition is terminated by others, such as
// the input focus is grabbed by another application.
// if forced is false, the composition is terminated gracefully by endComposition().
// virtual
void TextService::onCompositionTerminated(bool forced) {
	// we do special handling here for forced composition termination.
	if(forced) {
		// we're still editing our composition and have something in the preedit buffer.
		// however, some other applications grabs the focus and force us to terminate
		// our composition.
		if (showingCandidates()) // disable candidate window if it's opened
			hideCandidates();
		hideMessage(); // hide message window, if there's any
	}
	if(client_)
		client_->onCompositionTerminated(forced);
}

void TextService::onLangProfileActivated(REFIID lang) {
	// Sometimes, Windows does not deactivate the old language profile before
	// activating the new one. So here we do it by ourselves.
	// If a new profile is activated, but there is an old one remaining active,
	// deactive it first.
	if (client_ != nullptr)
		closeClient();

	// create a new client connection to the input method server for the language profile
	client_ = std::make_unique<Client>(this, lang);
	client_->onActivate();
}

void TextService::onLangProfileDeactivated(REFIID lang) {
	closeClient();
}

void TextService::createCandidateWindow(Ime::EditSession* session) {
	if (!candidateWindow_) {
		candidateWindow_ = new Ime::CandidateWindow(this, session); // assigning to smart ptr also inrease ref count
		candidateWindow_->Release();  // decrease ref count caused by new

		candidateWindow_->setFont(font_);
		BOOL hostRequestsOwnedWindow = TRUE;
		auto elementMgr = Ime::ComPtr<ITfUIElementMgr>::queryFrom(threadMgr());
		if (elementMgr) {
			validCandidateListElementId_ =
				(elementMgr->BeginUIElement(candidateWindow_, &hostRequestsOwnedWindow, &candidateListElementId_) == S_OK);
		}
		candidateWindow_->Show(shouldShowOwnedCandidateWindow(
			validCandidateListElementId_, hostRequestsOwnedWindow));
	}
}

void TextService::updateCandidates(Ime::EditSession* session) {
	createCandidateWindow(session);
	candidateWindow_->clear();

	// Apply deferred font changes immediately before measuring candidate rows,
	// so candidate and message window sizes use the same current font.
	if (updateFont_) {
		// font for candidate and mesasge windows
		LOGFONT lf;
		GetObject(font_, sizeof(lf), &lf);
		::DeleteObject(font_); // delete old font
		lf.lfHeight = candFontHeight(); // apply the new size
		if (!candFontName_.empty()) { // apply new font name
			wcsncpy(lf.lfFaceName, candFontName_.c_str(), 31);
		}
		font_ = CreateFontIndirect(&lf); // create new font
		if (messageWindow_)
			messageWindow_->setFont(font_);
		if (candidateWindow_)
			candidateWindow_->setFont(font_);
		updateFont_ = false;
	}

	candidateWindow_->setUseCursor(candUseCursor_);
	candidateWindow_->setCandPerRow(candPerRow_);

	// the items in the candidate list should not exist the
	// number of available keys used to select them.
	assert(candidates_.size() <= selKeys_.size());
	for (int i = 0; i < candidates_.size(); ++i) {
		const std::wstring label = i < selLabels_.size() ? selLabels_[i] : std::wstring();
		candidateWindow_->add(candidates_[i], selKeys_[i], label);
	}
	candidateWindow_->recalculateSize();
	candidateWindow_->refresh();

	RECT textRect;
	// get the position of composition area from TSF
	if (selectionRect(session, &textRect)) {
		movePopupNearSelection(candidateWindow_->hwnd(), textRect);
	}

	if (validCandidateListElementId_) {
		auto elementMgr = Ime::ComPtr<ITfUIElementMgr>::queryFrom(threadMgr());
		if (elementMgr) {
			elementMgr->UpdateUIElement(candidateListElementId_);
		}
	}
}

void TextService::updateCandidatesWindow(Ime::EditSession* session) {
    if (candidateWindow_) {
        RECT textRect;
        // get the position of composition area from TSF
        if (selectionRect(session, &textRect)) {
			movePopupNearSelection(candidateWindow_->hwnd(), textRect);
        }
    }
}

void TextService::refreshCandidates() {
	if (validCandidateListElementId_) {
		auto elementMgr = Ime::ComPtr<ITfUIElementMgr>::queryFrom(threadMgr());
		if (elementMgr) {
			elementMgr->UpdateUIElement(candidateListElementId_);
		}
	}
}

// show candidate list window
void TextService::showCandidates(Ime::EditSession* session) {
	// CandidateWindow implements ITfCandidateListUIElement. BeginUIElement decides
	// whether this process draws the window; UI-less hosts can render the list from
	// the COM element while the owned window remains hidden.
	createCandidateWindow(session);
	showingCandidates_ = true;
}

// hide candidate list window
void TextService::hideCandidates() {
	if (validCandidateListElementId_) {
		auto elementMgr = Ime::ComPtr<ITfUIElementMgr>::queryFrom(threadMgr());
		if (elementMgr) {
			elementMgr->EndUIElement(candidateListElementId_);
			candidateListElementId_ = 0;
			validCandidateListElementId_ = false;
		}
	}
	if (candidateWindow_) {
		candidateWindow_ = nullptr;
	}
	showingCandidates_ = false;
}

// message window
void TextService::showMessage(Ime::EditSession* session, std::wstring message, int duration) {
	// Reuse the existing message window while the TSF composition owner stays the
	// same. A focus change gets a new owner window to avoid attaching UI to a stale
	// application window.
	hideMessage();
	const HWND owner = compositionWindow(session);
	if (messageWindow_ && ::GetWindow(messageWindow_->hwnd(), GW_OWNER) != owner) {
		messageWindow_ = nullptr;
	}
	if (!messageWindow_) {
		messageWindow_ = make_unique<Ime::MessageWindow>(this, session);
	}
	messageWindow_->setFont(font_);
	messageWindow_->setText(message);
	
	bool positioned = false;
	if(isComposing()) {
		RECT rc;
		if(selectionRect(session, &rc)) {
			movePopupNearSelection(messageWindow_->hwnd(), rc);
			positioned = true;
		}
	}
	if (!positioned) {
		messageWindow_->move(0, 0);
	}
	messageWindow_->show();

	messageTimerId_ = ::SetTimer(messageWindow_->hwnd(), 1, duration * 1000, (TIMERPROC)TextService::onMessageTimeout);
}

void TextService::updateMessageWindow(Ime::EditSession* session) {
    if (messageWindow_) {
        RECT textRect;
        // get the position of composition area from TSF
        if (selectionRect(session, &textRect)) {
			movePopupNearSelection(messageWindow_->hwnd(), textRect);
        }
    }
}

void TextService::hideMessage() {
	if(messageTimerId_) {
		if (messageWindow_) {
			::KillTimer(messageWindow_->hwnd(), messageTimerId_);
		}
		messageTimerId_ = 0;
	}
	if(messageWindow_) {
		messageWindow_->hide();
	}
}

void TextService::destroyMessageWindow() {
	hideMessage();
	messageWindow_ = nullptr;
}

// called when the message window timeout
void TextService::onMessageTimeout() {
	hideMessage();
}

// static
void CALLBACK TextService::onMessageTimeout(HWND hwnd, UINT msg, UINT_PTR id, DWORD time) {
	Ime::MessageWindow* messageWindow = (Ime::MessageWindow*)Ime::Window::fromHwnd(hwnd);
	assert(messageWindow);
	if(messageWindow) {
		TextService* pThis = (PIME::TextService*)messageWindow->textService();
		pThis->onMessageTimeout();
	}
}


void TextService::updateLangButtons() {
}

int TextService::candFontHeight() {
	int candFontHeight_ = candFontSize_;
	HDC hdc = GetDC(NULL);
	if (hdc)
	{
		candFontHeight_ = -MulDiv(candFontSize_, GetDeviceCaps(hdc, LOGPIXELSY), 72);
		ReleaseDC(NULL, hdc);
	}
	return candFontHeight_;
}

void TextService::closeClient() {
	// deactive currently active language profile
	if (client_) {
		// disconnect from the server
		client_->onDeactivate();
		client_ = nullptr;
		// detroy UI resources
		destroyMessageWindow();
		hideCandidates();
	}
}

} // namespace PIME
