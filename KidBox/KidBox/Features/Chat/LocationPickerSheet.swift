import SwiftUI
import CoreLocation
import MapKit

struct LocationPickerSheet: View {
    
    @Environment(\.dismiss) private var dismiss
    @StateObject private var provider = KBLocationProvider()
    
    let onSend: (_ lat: Double, _ lon: Double) -> Void
    
    @State private var cameraPosition: MapCameraPosition =
        .region(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 41.0, longitude: 14.8),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        )
    
    var body: some View {
        ZStack {
            
            // 🔵 MAP FULLSCREEN
            Map(position: $cameraPosition) {
                if let loc = provider.location?.coordinate {
                    Marker("La tua posizione", coordinate: loc)
                        .tint(.red)
                }
            }
            .mapStyle(.standard)
            .ignoresSafeArea()
            
            // 🔵 BOTTOM BUTTON OVERLAY
            VStack {
                Spacer()
                
                if let loc = provider.location?.coordinate {
                    Button {
                        let rounded = roundPrivacy(loc)
                        onSend(rounded.latitude, rounded.longitude)
                        dismiss()
                    } label: {
                        Text("Invia posizione attuale")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .padding(.bottom, 40)
                }
            }
        }
        .onAppear {
            provider.request()
        }
        .onChange(of: provider.location) { _, newValue in
            guard let c = newValue?.coordinate else { return }
            
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: c,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
            )
        }
        .onDisappear {
            provider.stop()
        }
    }
    
    private func roundPrivacy(_ c: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        func r4(_ v: Double) -> Double { (v * 10_000).rounded() / 10_000 }
        return .init(latitude: r4(c.latitude), longitude: r4(c.longitude))
    }
}
