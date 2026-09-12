import SwiftUI

/// Task 8 에서 지도로 바뀐다. 지금은 합류가 끝나 화면이 넘어왔는지만 눈으로 본다.
struct ChildMapView: View {
    let familyId: String
    let childUid: String?

    var body: some View {
        VStack(spacing: 8) {
            Text(verbatim: familyId)
            Text(verbatim: childUid ?? "-")
        }
    }
}
