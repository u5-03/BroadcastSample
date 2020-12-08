//
//  ViewController.swift
//  BroadcastSample
//
//  Created by Yugo Sugiyama on 2020/10/18.
//

import UIKit
enum Section: Hashable {
    case main
}

enum SampleType: String, CaseIterable {
    case player
    case audioEngine

    var title: String {
        return rawValue.prefix(1).capitalized + rawValue.dropFirst()
    }

    var viewController: UIViewController {
        switch self {
        case .player: return PlayerViewController.instance()
        case .audioEngine: return AudioEngineViewController.instance()
        }
    }
}

class ViewController: UIViewController {
    @IBOutlet weak var collectionView: UICollectionView!
    var dataSource: UICollectionViewDiffableDataSource<Section, SampleType>? = nil

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "BroadSample"
        // Ref: https://medium.com/better-programming/build-simpler-more-modern-collection-views-in-ios-14-ca74eab2bb89
        let cellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, SampleType> { (cell, indexPath, item) in
            var content = cell.defaultContentConfiguration()
            content.text = "\(indexPath.row): " + item.title
            cell.contentConfiguration = content
        }

        dataSource = UICollectionViewDiffableDataSource<Section, SampleType>(collectionView: collectionView) {
            (collectionView: UICollectionView, indexPath: IndexPath, identifier: SampleType) -> UICollectionViewCell? in
            return collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: identifier)
        }
        var snapshot = NSDiffableDataSourceSnapshot<Section, SampleType>()
        snapshot.appendSections([.main])
        snapshot.appendItems(SampleType.allCases)
        dataSource?.apply(snapshot, animatingDifferences: false)

        let config = UICollectionLayoutListConfiguration(appearance: .plain)
        let layout = UICollectionViewCompositionalLayout.list(using: config)
        collectionView.collectionViewLayout = layout
    }
}

extension ViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let type = SampleType.allCases[indexPath.row]
        let vc = type.viewController
        vc.title = type.title
        collectionView.deselectItem(at: indexPath, animated: false)
        navigationController?.pushViewController(vc, animated: true)
    }
}
