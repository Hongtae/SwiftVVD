#if ENABLE_WIN32
import WinSDK
import Foundation

struct Win32DropTarget {
    internal private(set) var dropTarget: IDropTarget = IDropTarget()
    internal private(set) var vtbl: IDropTargetVtbl = IDropTargetVtbl()
    private var refCount: Int = 1
    private var thisPointer: UnsafeMutablePointer<Win32DropTarget>?

    private mutating func queryInterface(_ riid: UnsafePointer<IID>?,
                                            _ ppv: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> HRESULT {
        Log.debug("queryInterface")
        let isEqualIID = { (iid1: UnsafePointer<IID>, id2: IID)->Bool in
            withUnsafePointer(to: id2) { ptr2 in
                memcmp(iid1, ptr2, MemoryLayout<IID>.size) == 0
            }               
        };
        if isEqualIID(riid!, IID_IUnknown) || isEqualIID(riid!, IID_IDropTarget) {
            withUnsafeMutablePointer(to: &self) {
                ptr in ppv!.pointee = UnsafeMutableRawPointer(ptr)
            }
            _ = self.addRef()
            return S_OK;
        }
        ppv!.pointee = nil
        return HRESULT(bitPattern:0x80004002) // E_NOINTERFACE
    }
    private mutating func addRef() -> ULONG {
        self.refCount += 1
        Log.debug("DropTarget.addRef: \(self.refCount)")
        return ULONG(self.refCount)
    }
    private mutating func release() -> ULONG {
        self.refCount -= 1
        Log.debug("DropTarget.release: \(self.refCount)")
        if self.refCount == 0 {
            Log.debug("DropTarget deallocate!")

            let ptr: UnsafeMutablePointer<Win32DropTarget> = self.thisPointer!
            ptr.deinitialize(count: 1)
            ptr.deallocate()
            return 0
        }
        return ULONG(self.refCount)
    }

    private weak var target: Win32Window?
    private var files: [String] = []
    private var dropAllowed = false
    private var lastEffectMask: DWORD = DWORD(DROPEFFECT_NONE)
    private var lastPosition: POINT = POINT()
    private var lastKeyState: DWORD = DWORD(0)
    private var periodicUpdate: Bool = false

    private static func filesFromDataObject(_ dataObject: inout IDataObject) -> [String] {
        var files: [String] = []
        var fmtetc: FORMATETC = FORMATETC(cfFormat: UInt16(CF_HDROP),
                                                ptd: nil,
                                        dwAspect: DWORD(DVASPECT_CONTENT.rawValue),
                                            lindex: -1,
                                            tymed: DWORD(TYMED_HGLOBAL.rawValue))
        var stgm: STGMEDIUM = STGMEDIUM()
        if dataObject.lpVtbl.pointee.GetData(&dataObject, &fmtetc, &stgm) >= 0 {
            let hdrop: HDROP = unsafeBitCast(stgm.hGlobal, to:HDROP.self)
            let numFiles = DragQueryFileW(hdrop, 0xFFFFFFFF, nil, 0)
            for index in 0..<numFiles {
                let len = DragQueryFileW(hdrop, index, nil, 0)
                var buff = [WCHAR](repeating:0, count:Int(len+2))
                let file = buff.withUnsafeMutableBufferPointer { ptr -> String in
                    let r = DragQueryFileW(hdrop, index, ptr.baseAddress, len+1)
                    ptr[Int(r)] = WCHAR(0)
                    return String(decodingCString: ptr.baseAddress!, as: UTF16.self)
                }
                files.append(file)
            }
        }
        return files
    }
    private mutating func dragEnter(_ pDataObj: UnsafeMutablePointer<IDataObject>?,
                                    _ grfKeyState: DWORD,
                                    _ pt: POINTL,
                                    _ pdwEffect: UnsafeMutablePointer<DWORD>?) -> HRESULT {
        self.files = [String]()
        self.dropAllowed = false
        self.lastEffectMask = DWORD(DROPEFFECT_NONE)

        let delegate = self.target?.delegate
        if  delegate != nil {
            var fmtetc: FORMATETC = FORMATETC(cfFormat: UInt16(CF_HDROP),
                                                ptd: nil,
                                            dwAspect: DWORD(DVASPECT_CONTENT.rawValue),
                                                lindex: -1,
                                                tymed: DWORD(TYMED_HGLOBAL.rawValue))
            if pDataObj!.pointee.lpVtbl.pointee.QueryGetData(pDataObj, &fmtetc) == S_OK {
                self.files = Self.filesFromDataObject(&pDataObj!.pointee)
                if self.files.count > 0 {
                    self.dropAllowed = true
                }
            }
        }

        if self.dropAllowed {
            var pos: POINT = POINT(x: pt.x, y: pt.y)
            ScreenToClient(target!.hWnd, &pos)

            self.lastKeyState = grfKeyState
            self.lastPosition = pos

            let op = delegate!.draggingEntered(target: self.target!, 
                                                position: CGPoint(x: Int(pos.x),
                                                                y: Int(pos.y)),
                                                files: self.files)
            switch op {
            case .copy: self.lastEffectMask = DWORD(DROPEFFECT_COPY)
            case .move: self.lastEffectMask = DWORD(DROPEFFECT_MOVE)
            case .link: self.lastEffectMask = DWORD(DROPEFFECT_LINK)
            case .none: self.lastEffectMask = DWORD(DROPEFFECT_NONE)  
            default: // .reject
                self.lastEffectMask = DWORD(DROPEFFECT_NONE)
                self.dropAllowed = false
            }
            pdwEffect!.pointee &= self.lastEffectMask
        } else {
            pdwEffect!.pointee = DWORD(DROPEFFECT_NONE)
        }
        return S_OK;
    }
    private mutating func dragOver(_ grfKeyState: DWORD,
                                    _ pt: POINTL,
                                    _ pdwEffect: UnsafeMutablePointer<DWORD>?) -> HRESULT {

        if let delegate = self.target?.delegate, self.dropAllowed {
            var pos: POINT = POINT(x: pt.x, y: pt.y)
            ScreenToClient(target!.hWnd, &pos)

            var update = true
            if periodicUpdate == false && 
                self.lastPosition.x == pos.x &&
                self.lastPosition.y == pos.y &&
                self.lastKeyState == grfKeyState {
                    update = false
            }

            if update {
                self.lastKeyState = grfKeyState
                self.lastPosition = pos

                let op = delegate.draggingUpdated(target: self.target!, 
                                                position: CGPoint(x: Int(pos.x),
                                                                    y: Int(pos.y)),
                                                    files: self.files)
                switch op {
                case .copy: self.lastEffectMask = DWORD(DROPEFFECT_COPY)
                case .move: self.lastEffectMask = DWORD(DROPEFFECT_MOVE)
                case .link: self.lastEffectMask = DWORD(DROPEFFECT_LINK)
                case .none: self.lastEffectMask = DWORD(DROPEFFECT_NONE)  
                default: // .reject
                    self.lastEffectMask = DWORD(DROPEFFECT_NONE)
                    self.dropAllowed = false
                }
            }
            pdwEffect!.pointee &= self.lastEffectMask
        } else {
            self.dropAllowed = false
            pdwEffect!.pointee = DWORD(DROPEFFECT_NONE)
        }
        return S_OK;
    }
    private mutating func dragLeave() -> HRESULT {
        if let delegate = self.target?.delegate, self.dropAllowed {
            delegate.draggingExited(target: self.target!, files: self.files)
        } else {
            self.dropAllowed = false
        }
        self.files = [String]()
        self.lastEffectMask = DWORD(DROPEFFECT_NONE)        
        return S_OK;
    }
    private mutating func drop(_ pDataObj: UnsafeMutablePointer<IDataObject>?,
                        _ grfKeyState: DWORD,
                        _ pt: POINTL,
                        _ pdwEffect: UnsafeMutablePointer<DWORD>?) -> HRESULT {

        if let delegate = self.target?.delegate, self.dropAllowed {
            var pos: POINT = POINT(x: pt.x, y: pt.y)
            ScreenToClient(target!.hWnd, &pos)

            self.lastKeyState = grfKeyState
            self.lastPosition = pos

            let op = delegate.draggingDropped(target: self.target!, 
                                            position: CGPoint(x: Int(pos.x),
                                                                y: Int(pos.y)),
                                                files: self.files)
            switch op {
            case .copy: self.lastEffectMask = DWORD(DROPEFFECT_COPY)
            case .move: self.lastEffectMask = DWORD(DROPEFFECT_MOVE)
            case .link: self.lastEffectMask = DWORD(DROPEFFECT_LINK)
            case .none: self.lastEffectMask = DWORD(DROPEFFECT_NONE)  
            default: // .reject
                self.lastEffectMask = DWORD(DROPEFFECT_NONE)
                self.dropAllowed = false
            }
            pdwEffect!.pointee &= self.lastEffectMask
        } else {
            self.dropAllowed = false
            pdwEffect!.pointee = DWORD(DROPEFFECT_NONE)
        }
        self.files = [String]()
        self.lastEffectMask = DWORD(DROPEFFECT_NONE)        
        return S_OK;
    }
    static func makeMutablePointer(target: Win32Window) -> UnsafeMutablePointer<Win32DropTarget> {
        let dt: UnsafeMutablePointer<Win32DropTarget> = .allocate(capacity: 1)
        dt.initialize(to: Win32DropTarget(target: target))
        
        // *** IUnknown ***
        dt.pointee.vtbl.QueryInterface = { ptr, riid, ppv in
            let dt = UnsafeMutableRawPointer(ptr!).bindMemory(to: Win32DropTarget.self, capacity: 1)
            return dt.pointee.queryInterface(riid, ppv)
        }
        dt.pointee.vtbl.AddRef = { ptr in 
            let dt = UnsafeMutableRawPointer(ptr!).bindMemory(to: Win32DropTarget.self, capacity: 1)
            return dt.pointee.addRef()
        }
        dt.pointee.vtbl.Release = { ptr in 
            let dt = UnsafeMutableRawPointer(ptr!).bindMemory(to: Win32DropTarget.self, capacity: 1)
            return dt.pointee.release()
        }

        // *** IDropTarget ***
        dt.pointee.vtbl.DragEnter = { ptr, pDataObj, grfKeyState, pt, pdwEffect in 
            let dt = UnsafeMutableRawPointer(ptr!).bindMemory(to: Win32DropTarget.self, capacity: 1)
            return dt.pointee.dragEnter(pDataObj, grfKeyState, pt, pdwEffect)
        }
        dt.pointee.vtbl.DragOver = { ptr, grfKeyState, pt, pdwEffect in 
            let dt = UnsafeMutableRawPointer(ptr!).bindMemory(to: Win32DropTarget.self, capacity: 1)
            return dt.pointee.dragOver(grfKeyState, pt, pdwEffect)
        }
        dt.pointee.vtbl.DragLeave = { ptr in 
            let dt = UnsafeMutableRawPointer(ptr!).bindMemory(to: Win32DropTarget.self, capacity: 1)
            return dt.pointee.dragLeave()
        }
        dt.pointee.vtbl.Drop = { ptr, pDataObj, grfKeyState, pt, pdwEffect in 
            let dt = UnsafeMutableRawPointer(ptr!).bindMemory(to: Win32DropTarget.self, capacity: 1)
            return dt.pointee.drop(pDataObj, grfKeyState, pt, pdwEffect)
        }

        // setup IDropTarget interface (lpVtbl)
        withUnsafeMutablePointer(to: &dt.pointee.vtbl) {
            dt.pointee.dropTarget.lpVtbl = $0
        }
        dt.pointee.thisPointer = dt
        return dt
    }
}
#endif //if ENABLE_WIN32