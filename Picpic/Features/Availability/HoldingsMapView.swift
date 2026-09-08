//
//  HoldingsMapView.swift
//  Picpic
//
//  Où trouver ce livre, sur une carte plutôt que dans une liste.
//
//  Le Sudoc renvoie déjà les coordonnées des bibliothèques détentrices (service
//  multiwhere d'ABES) : une liste de noms abrégés — « LA ROCHELLE-BU », « PARIS-
//  SORBONNE » — ne dit rien à un étudiant, alors qu'un point sur une carte
//  répond en une seconde à la seule question qui compte, « est-ce que c'est
//  près de moi ? ».
//
//  La carte ne demande PAS la position de l'utilisateur, et c'est délibéré :
//  docs/PRIVACY.md annonce qu'aucune donnée de localisation n'est collectée, et
//  le paywall vend une app sans serveurs. Montrer où sont les bibliothèques ne
//  coûte aucune autorisation ; savoir où est le lecteur en coûterait une, et
//  obligerait à réécrire cette promesse. La carte se cadre donc sur les
//  bibliothèques elles-mêmes.
//

import MapKit
import SwiftUI

/// Carte des bibliothèques détentrices, avec la liste en dessous.
struct HoldingsMapView: View {
    let holdings: [HoldingLibrary]
    var onSelect: (HoldingLibrary) -> Void = { _ in }

    @State private var camera: MapCameraPosition = .automatic
    @State private var selected: String?
    @State private var framed = false

    /// Bibliothèques réellement plaçables : le Sudoc laisse parfois les
    /// coordonnées vides, et une annotation sans point n'a nulle part où aller.
    private var located: [(library: HoldingLibrary, point: CLLocationCoordinate2D)] {
        holdings.compactMap { lib in lib.coordinate.map { (lib, $0) } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if located.isEmpty {
                unlocatedNotice
            } else {
                map
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Theme.ink.opacity(0.08))
                    )
                    .accessibilityIdentifier("availability.map")
            }

            list
        }
        .padding(14)
        .background(Theme.teal.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        // Une seule fois : recadrer à chaque réapparition effacerait le
        // déplacement que l'utilisateur vient de faire sur la carte.
        .onAppear {
            guard !framed else { return }
            framed = true
            camera = .region(Self.region(around: located.map(\.point)))
        }
    }

    private var header: some View {
        Label("Dispo dans \(holdings.count) BU en France (Sudoc)",
              systemImage: "building.columns.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.ink)
    }

    private var map: some View {
        Map(position: $camera, selection: $selected) {
            ForEach(located, id: \.library.id) { entry in
                Marker(entry.library.name, systemImage: "building.columns.fill",
                       coordinate: entry.point)
                    .tint(Theme.teal)
                    .tag(entry.library.id)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls { MapCompass() }
        .onChange(of: selected) { _, id in
            if let entry = located.first(where: { $0.library.id == id }) { onSelect(entry.library) }
        }
    }

    private var unlocatedNotice: some View {
        Text("Le Sudoc ne donne pas les coordonnées de ces bibliothèques.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(holdings.prefix(5)) { library in
                Button {
                    onSelect(library)
                    if let coordinate = library.coordinate {
                        withAnimation(.snappy) {
                            camera = .region(MKCoordinateRegion(
                                center: coordinate,
                                span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)))
                            selected = library.id
                        }
                    }
                } label: {
                    HStack {
                        Text(library.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        if library.coordinate == nil {
                            Image(systemName: "mappin.slash")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("availability.row")
            }
            if holdings.count > 5 {
                Text("et \(holdings.count - 5) autres")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// Cadre englobant les bibliothèques, avec une marge.
    ///
    /// `.automatic` suffirait pour plusieurs points, mais donne un zoom absurde
    /// quand il n'y en a qu'un : on impose alors une fenêtre lisible.
    static func region(around points: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard let first = points.first else {
            // Repli : la France entière, plutôt qu'un océan.
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 46.6, longitude: 2.5),
                span: MKCoordinateSpan(latitudeDelta: 10, longitudeDelta: 10))
        }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for p in points.dropFirst() {
            minLat = min(minLat, p.latitude);  maxLat = max(maxLat, p.latitude)
            minLon = min(minLon, p.longitude); maxLon = max(maxLon, p.longitude)
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                           longitude: (minLon + maxLon) / 2),
            // Plafonné : entre la métropole et les DOM-TOM, l'écart peut
            // dépasser les 360° qu'accepte une région.
            span: MKCoordinateSpan(
                latitudeDelta: min(max((maxLat - minLat) * 1.4, 0.12), 170),
                longitudeDelta: min(max((maxLon - minLon) * 1.4, 0.12), 350)))
    }
}
