import WinSDK
import Foundation

    enum DragOperation {
        case none, copy, move, link
    }
    protocol DropTargetDelegate {
        func draggingEntered(files:[String], keyState: DWORD, pt: POINTL) -> DragOperation
        func draggingUpdated(files:[String], keyState: DWORD, pt: POINTL) -> DragOperation
        func draggingExited(files:[String], pt: POINTL) -> DragOperation
        func draggingDropped(files:[String], pt: POINTL) -> DragOperation
    }

extension Win32 {

    struct DropTarget {
        private var dropTarget: IDropTarget = IDropTarget()
        private var vtbl: IDropTargetVtbl = IDropTargetVtbl()
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
            NSLog("addRef")
            self.refCount += 1
            return ULONG(self.refCount)
        }
        private mutating func release() -> ULONG {
            NSLog("release")
            self.refCount -= 1
            if self.refCount == 0 {
                NSLog("dealloc!")

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
            dt.pointee.vtbl.QueryInterface = { dt, riid, ppv in
                dt!.withMemoryRebound(to: DropTarget.self, capacity:1) {
                    dropTarget in dropTarget.pointee.queryInterface(riid, ppv)
                }
                // return S_OK
            }
            dt.pointee.vtbl.AddRef = { dt in 
                dt!.withMemoryRebound(to: DropTarget.self, capacity:1) {
                    dropTarget in dropTarget.pointee.addRef()
                }
            }
            dt.pointee.vtbl.Release = { dt in 
                dt!.withMemoryRebound(to: DropTarget.self, capacity:1) {
                    dropTarget in dropTarget.pointee.release()
                }
            }
            dt.pointee.vtbl.DragEnter = { dt, pDataObj, grfKeyState, pt, pdwEffect in 
                dt!.withMemoryRebound(to: DropTarget.self, capacity:1) {
                    dropTarget in dropTarget.pointee.dragEnter(pDataObj, grfKeyState, pt, pdwEffect)
                }
            }
            dt.pointee.vtbl.DragOver = { dt, grfKeyState, pt, pdwEffect in 
                dt!.withMemoryRebound(to: DropTarget.self, capacity:1) {
                    dropTarget in dropTarget.pointee.dragOver(grfKeyState, pt, pdwEffect)
                }
            }
            dt.pointee.vtbl.DragLeave = { dt in 
                dt!.withMemoryRebound(to: DropTarget.self, capacity:1) {
                    dropTarget in dropTarget.pointee.dragLeave()
                }
            }
            dt.pointee.vtbl.Drop = { dt, pDataObj, grfKeyState, pt, pdwEffect in 
                dt!.withMemoryRebound(to: DropTarget.self, capacity:1) {
                    dropTarget in dropTarget.pointee.drop(pDataObj, grfKeyState, pt, pdwEffect)
                }
            }
            withUnsafeMutablePointer(to: &dt.pointee.vtbl) {
                dt.pointee.dropTarget.lpVtbl = $0
            }
            dt.pointee.thisPointer = dt
            return dt
        }
    }
}