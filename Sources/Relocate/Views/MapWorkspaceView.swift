import MapKit
import SwiftUI

struct MapWorkspaceView: View {
    @Environment(AppModel.self) private var model
    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 47.4979, longitude: 19.0402),
            span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
        )
    )

    var body: some View {
        MapReader { proxy in
            Map(position: $camera) {
                Marker(model.selectedPoint.name, coordinate: model.selectedPoint.coordinate)
                    .tint(.blue)

                ForEach(Array(model.route.enumerated()), id: \.element.id) { index, point in
                    Annotation("Waypoint \(index + 1)", coordinate: point.coordinate) {
                        Text("\(index + 1)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(.purple))
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                            .shadow(radius: 3)
                    }
                }

                if model.route.count >= 2 {
                    MapPolyline(coordinates: model.route.map(\.coordinate))
                        .stroke(.purple, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                }

                if let cursor = model.routeCursor {
                    Annotation("Current position", coordinate: cursor.coordinate, anchor: .center) {
                        RoutePositionMarker()
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .all, showsTraffic: false))
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { event in
                        guard let coordinate = proxy.convert(event.location, from: .local) else { return }
                        model.select(
                            point: LocationPoint(
                                name: "Dropped Pin",
                                latitude: coordinate.latitude,
                                longitude: coordinate.longitude
                            )
                        )
                    }
            )
        }
        .overlay(alignment: .top) {
            SearchOverlay(camera: $camera)
                .padding(16)
        }
        .overlay(alignment: .bottomLeading) {
            LocationCard()
                .padding(16)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            StatusBar()
        }
        .onChange(of: model.selectedPoint) { _, point in
            withAnimation(.easeInOut(duration: 0.35)) {
                camera = .region(
                    MKCoordinateRegion(
                        center: point.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06)
                    )
                )
            }
        }
    }
}

/// Pulsing blue dot marking the device's live position along a playing route.
private struct RoutePositionMarker: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(.blue.opacity(0.22))
                .frame(width: 44, height: 44)
                .scaleEffect(pulse ? 1.0 : 0.4)
                .opacity(pulse ? 0 : 0.9)

            Circle()
                .fill(.blue)
                .frame(width: 18, height: 18)
                .overlay(Circle().stroke(.white, lineWidth: 3))
                .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}

private struct SearchOverlay: View {
    @Environment(AppModel.self) private var model
    @Binding var camera: MapCameraPosition

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search places or addresses", text: $model.searchText)
                    .textFieldStyle(.plain)
                    .onSubmit { model.search() }
                    .onChange(of: model.searchText) { _, _ in model.search() }
                if model.isSearching {
                    ProgressView().controlSize(.small)
                } else if !model.searchText.isEmpty {
                    Button {
                        model.searchText = ""
                        model.searchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)

            if !model.searchResults.isEmpty {
                Divider()
                VStack(spacing: 0) {
                    ForEach(Array(model.searchResults.enumerated()), id: \.offset) { _, item in
                        Button {
                            model.chooseSearchResult(item)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "mappin.circle")
                                    .foregroundStyle(.blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name ?? "Location")
                                        .fontWeight(.medium)
                                        .lineLimit(1)
                                    Text(item.placemark.title ?? "")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 50)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: 480)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.22)))
        .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
    }
}

private struct LocationCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.circle.fill")
                .font(.title2)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.selectedPoint.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(model.selectedPoint.coordinateLabel)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Divider().frame(height: 26)

            Button {
                model.addSelectedToRoute()
            } label: {
                Image(systemName: "plus")
            }
            .help("Add as route waypoint")

            Menu {
                Button("Copy Coordinates", systemImage: "doc.on.doc") { model.copyCoordinates() }
                Button("Save Place", systemImage: "star") { model.saveSelectedPlace() }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 340)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.18)))
        .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
    }
}
