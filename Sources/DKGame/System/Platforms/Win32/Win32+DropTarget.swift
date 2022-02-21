import WinSDK
import Foundation

extension Win32 {

    struct DropTarget {
        internal private(set) var dropTarget: IDropTarget = IDropTarget()
        internal private(set) var vtbl: IDropTargetVtbl = IDropTargetVtbl()
        private var refCount: Int = 1
        private var thisPointer: UnsafeMutablePointer<DropTarget>?

        private mutating func queryInterface(_ riid: UnsafePointer<IID>?, _  ppv: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> HRESULT {
            NSLog("queryInterface")
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
            NSLog("DropTarget.addRef: \(self.refCount)")
            return ULONG(self.refCount)
        }
        private mutating func release() -> ULONG {
            self.refCount -= 1
            NSLog("DropTarget.release: \(self.refCount)")
            if self.refCount == 0 {
                NSLog("DropTarget deallocate!")

                let ptr: UnsafeMutablePointer<DropTarget> = self.thisPointer!
                ptr.deinitialize(count: 1)
                ptr.deallocate()
                return 0
            }
            return ULONG(self.refCount)
        }
        private func dragEnter(_ pDataObj: UnsafeMutablePointer<IDataObject>?, _ grfKeyState: DWORD, _ pt: POINTL, _ pdwEffect: UnsafeMutablePointer<DWORD>?) -> HRESULT {
            NSLog("dragEnter")
            return S_OK;
        }
        private func dragOver(_ grfKeyState: DWORD, _ pt: POINTL, _ pdwEffect: UnsafeMutablePointer<DWORD>?) -> HRESULT {
            NSLog("dragOver")
            return S_OK;
        }
        private func dragLeave() -> HRESULT {
            NSLog("dragLeave")
            return S_OK;
        }
        private func drop(_ pDataObj: UnsafeMutablePointer<IDataObject>?, _ grfKeyState: DWORD, _ pt: POINTL, _ pdwEffect: UnsafeMutablePointer<DWORD>?) -> HRESULT {
            NSLog("drop")
            return S_OK;
        }
        static func makeMutablePointer() -> UnsafeMutablePointer<DropTarget> {
            let dt: UnsafeMutablePointer<DropTarget> = .allocate(capacity: 1)
            dt.initialize(to: DropTarget())
            // setup IDropTarget interface
            dt.pointee.vtbl.QueryInterface = { ptr, riid, ppv in
                let dt = UnsafeMutableRawPointer(ptr!).bindMemory(to: DropTarget.self, capacity: 1)
                return dt.pointee.queryInterface(riid, ppv)
            }
            dt.pointee.vtbl.AddRef = { ptr in 
                let dt = UnsafeMutableRawPointer(ptr!).bindMemory(to: DropTarget.self, capacity: 1)
                return dt.pointee.addRef()
            }
            dt.pointee.vtbl.Release = { ptr in 
                let dt = UnsafeMutableRawPointer(ptr!).bindMemory(to: DropTarget.self, capacity: 1)
                return dt.pointee.release()
            }
            dt.pointee.vtbl.DragEnter = { ptr, pDataObj, grfKeyState, pt, pdwEffect in 
                let dt = UnsafeMutableRawPointer(ptr!).bindMemory(to: DropTarget.self, capacity: 1)
                return dt.pointee.dragEnter(pDataObj, grfKeyState, pt, pdwEffect)
            }
            dt.pointee.vtbl.DragOver = { ptr, grfKeyState, pt, pdwEffect in 
                let dt = UnsafeMutableRawPointer(ptr!).bindMemory(to: DropTarget.self, capacity: 1)
                return dt.pointee.dragOver(grfKeyState, pt, pdwEffect)
            }
            dt.pointee.vtbl.DragLeave = { ptr in 
                let dt = UnsafeMutableRawPointer(ptr!).bindMemory(to: DropTarget.self, capacity: 1)
                return dt.pointee.dragLeave()
            }
            dt.pointee.vtbl.Drop = { ptr, pDataObj, grfKeyState, pt, pdwEffect in 
                let dt = UnsafeMutableRawPointer(ptr!).bindMemory(to: DropTarget.self, capacity: 1)
                return dt.pointee.drop(pDataObj, grfKeyState, pt, pdwEffect)
            }
            withUnsafeMutablePointer(to: &dt.pointee.vtbl) {
                dt.pointee.dropTarget.lpVtbl = $0
            }
            dt.pointee.thisPointer = dt
            return dt
        }
    }
}