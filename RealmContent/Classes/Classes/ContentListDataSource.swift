//
//  RealmContentDataSource.swift
//  Created by Marin Todorov
//  Copyright © 2017 - present Realm. All rights reserved.
//

import Foundation
import UIKit
import RealmSwift

/// :nodoc:
/// Internal protocol to represent datasourceable struct
protocol DataSourceCollection {
    associatedtype Element
    var count: Int { get }
    subscript(position: Int) -> Element { get }
}

extension Array: DataSourceCollection { }
extension Results: DataSourceCollection { }

/**
 `ContentListDataSource` is a data source class that loads content from a Realm file
 and provides data to drive a table or collection view depending on the given settings 
 (e.g. plain list, sections, etc.)
 */
public class ContentListDataSource: NSObject {

    /// `plain` or `sectionsByTag` grouping style
    public enum Style {
        case plain
        case sectionsByTag
    }

    private let keyPriority = "priority"
    private let keyTag = "tag"
    private let keyElements = "elements"

    fileprivate let style: Style
    private var realmConfiguration: Realm.Configuration!

    private weak var view: UIView?

    fileprivate var results: Results<ContentPage>?
    private var resultsToken: NotificationToken?

    // MARK: - class initialization

    /// creates an instance with the given grouping style
    public init(style: Style = .plain) {
        self.style = style
        super.init()
    }

    /// "loads" the list of content from the given realm
    public func loadContent(from realm: Realm) {
        realmConfiguration = realm.configuration
        loadContent()
    }

    /**
     if set, automatically updates the given view with any real-time changes
     - parameter view: if either a `UITableView` or `UICollectionView` will 
       be be updated upon any changes to the Realm's content
     */
    public func updating(view: UIView) {
        self.view = view
    }

    // MARK: - private methods

    fileprivate struct SectionInfo {
        let title: String?
        let start: Int
        let count: Int
    }

    fileprivate var sections: [SectionInfo]?

    private func loadContent() {
        let realm = try! Realm(configuration: realmConfiguration)

        switch style {
        case .plain:
            results = realm.objects(ContentPage.self)
                .filter("\(keyElements).@count > 0")
                .sorted(byKeyPath: keyPriority, ascending: false)

            resultsToken = results?.addNotificationBlock { [weak self] change in
                guard let view = self?.view else { return }
                if let tableView = view as? UITableView { tableView.reloadData() }
                if let collectionView = view as? UICollectionView { collectionView.reloadData() }
            }

        case .sectionsByTag:
            results = realm.objects(ContentPage.self)
                .filter("\(keyElements).@count > 0")
                .sorted(by: [
                    SortDescriptor(keyPath: keyTag, ascending: true),
                    SortDescriptor(keyPath: keyPriority, ascending: false)
                    ])
            resultsToken = results?.addNotificationBlock { [weak self] change in
                guard let this = self else { return }

                switch change {
                case .initial:
                    this.reloadView()
                case .update(let results, let deletions, let insertions, let modifications):
                    if results.count > 0 || deletions.count > 0 {
                        this.sections = this.sections(for: results)
                    }
                    this.reloadView(changes: (deletions, insertions, modifications))
                default: break
                }
            }
            sections = sections(for: results)
        }
    }

    private func reloadView(changes: ([Int], [Int], [Int])? = nil) {
        guard let view = view else { return }
        if let tableView = view as? UITableView { tableView.reloadData() }
        if let collectionView = view as? UICollectionView { collectionView.reloadData() }
    }

    private func sections(for results: Results<ContentPage>?) -> [SectionInfo] {
        //build section indexes
        guard let results = results, let first = results.first else {
            return []
        }

        var sections = [SectionInfo]()
        var currentCategory = first.tag
        var count = 0
        var start = 0

        autoreleasepool {
            for (index, page) in results.enumerated() {
                if page.tag != currentCategory {
                    sections.append(SectionInfo(title: currentCategory, start: start, count: count))
                    currentCategory = page.tag
                    start = index
                    count = 1
                } else {
                    count += 1
                }
            }

            sections.append(SectionInfo(title: currentCategory, start: start, count: count))
        }
        return sections
    }

    // MARK: - public data source methods

    /// returns the list of content as an array, in case the data source is group array will be 2 dimensional
    public func asArray() -> Array<ContentPage> {
        guard let results = results else { fatalError("You need to load the content before calling asArray()") }
        return Array(results)
    }

    /// returns the list of content as Results object. It will crash if called for a grouped in sections data source
    public func asResults() -> Results<ContentPage> {
        guard let results = results else { fatalError("You need to load the content before calling asResults()") }
        return results
    }

    /// returns the number of sections in the data source. Always returns `1` for plain grouping style.
    public var numberOfSections: Int {
        switch style {
        case .plain:
            return 1
        case .sectionsByTag:
            return sections!.count
        }
    }

    /**
     returns the number of items for a given section
     - parameter section: the section in question
     - returns: the number of items in the section
     */
    public func numberOfItemsIn(section: Int) -> Int {
        switch style {
        case .plain:
            return results!.count
        case .sectionsByTag:
            return sections![section].count
        }
    }

    /**
     returns the title for a given section
     - parameter section: the section in question
     - returns: the String title for the given section. Returns `nil` when grouping style is `plain`.
     */
    public func titleForSection(section: Int) -> String? {
        switch style {
        case .plain:
            return nil
        case .sectionsByTag:
            return sections![section].title
        }
    }

    /**
     returns the `ContentPage` for given section and index
     - parameter section: the section index
     - parameter section: the item index inside the section
     - returns: a `ContentPage` found for the given section/index
     */
    public func itemAt(section: Int = -1, index: Int) -> ContentPage {
        switch style {
        case .plain:
            return results![index]
        case .sectionsByTag:
            let offset = sections![section].start
            return results![offset + index]
        }
    }

    /**
     returns the `ContentPage` for given `IndexPath`
     - parameter indexPath: the index path in question
     - returns: a `ContentPage` found for the given `IndexPath`
     */
    public func itemAt(indexPath: IndexPath) -> ContentPage {
        return itemAt(section: indexPath.section, index: indexPath.row)
    }
}