//
//  ComicInfo.swift
//  MetaComic
//
//  Created by Stardust on 2025-10-03.
//

import Foundation

enum ComicInfoXMLError: Error {
    case parsingFailed
}

class ComicInfoXML: XMLParser {
    public var parsed: ComicInfoModel
    private var parsingComicInfo = false
    private var parsingPages = false
    private var hasChildren = false
    private var prevElement: String = ""
    private var currentElement: String = ""
    private var currentContent: String = ""
    private var elementStack: [String] = []

    // Parsing state for <Pages>/<Page>
    private var currentPageAttributes: [String: String] = [:]
    private var parsedPages: [ComicPageInfo] = []

    override init(data: Data) {
        self.parsed = .init()

        super.init(data: data)
        self.delegate = self
    }
}

extension ComicInfoXML: XMLParserDelegate {

    // Called when opening tag (`<elementName>`) is found
    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String] = .init()) {

        currentContent = ""
        currentElement = elementName
        elementStack.append(elementName)

        switch elementName {
        case "ComicInfo":
            parsingComicInfo = true
            hasChildren = true
        case "Pages":
            parsingPages = true
            hasChildren = true
            parsedPages.removeAll(keepingCapacity: false)
        case "Page":
            if parsingPages {
                // capture attributes for this page
                currentPageAttributes = attributeDict
            }
            hasChildren = false
        default:
            hasChildren = false
        }
    }

    // Called when a character sequence is found
    func parser(_ parser: XMLParser,
                foundCharacters string: String) {
        guard parsingComicInfo else { return }

        if !hasChildren {
            currentContent += string
        }
    }

    // Called when closing tag (`</elementName>`) is found
    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        // Handle container/structural elements first
        switch elementName {
        case "ComicInfo":
            parsingComicInfo = false

        case "Pages":
            parsingPages = false
            if !parsedPages.isEmpty {
                parsed.Pages = parsedPages
            }

        case "Page":
            if parsingPages {
                var page = ComicPageInfo()

                if let image = currentPageAttributes["Image"]?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    page.Image = image
                }
                if let pageTypeStr = currentPageAttributes["Type"]?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    if let mapped = ComicPageType(rawValue: pageTypeStr) {
                        page.PageType = mapped
                    } else if let mapped = ComicPageType.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(pageTypeStr) == .orderedSame }) {
                        page.PageType = mapped
                    }
                }
                if let doublePageStr = currentPageAttributes["DoublePage"]?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    page.DoublePage = (doublePageStr as NSString).boolValue
                }
                if let imageSizeStr = currentPageAttributes["ImageSize"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                   let size = Int64(imageSizeStr) {
                    page.ImageSize = size
                }
                if let key = currentPageAttributes["Key"]?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    page.Key = key
                }
                if let bookmark = currentPageAttributes["Bookmark"]?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    page.Bookmark = bookmark
                }
                if let widthStr = currentPageAttributes["ImageWidth"]?.trimmingCharacters(in: .whitespacesAndNewlines), let w = Int(widthStr) {
                    page.ImageWidth = w
                }
                if let heightStr = currentPageAttributes["ImageHeight"]?.trimmingCharacters(in: .whitespacesAndNewlines), let h = Int(heightStr) {
                    page.ImageHeight = h
                }

                parsedPages.append(page)
                currentPageAttributes.removeAll(keepingCapacity: false)
            }

        default:
            break
        }

        // Assign simple text content to model keys for non-container elements
        if parsingComicInfo && !parsingPages {
            let trimmed = currentContent.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && elementName != "ComicInfo" && elementName != "Pages" && elementName != "Page" {
                _ = parsed.set(key: elementName, value: trimmed)
            }
        }

        // Reset current content buffer for the next element
        currentContent = ""

        // Maintain an element stack to correctly track nesting
        if let last = elementStack.last, last == elementName {
            elementStack.removeLast()
        } else {
            // If the stack got out of sync, clear it to avoid cascading errors
            elementStack.removeAll(keepingCapacity: false)
        }
        prevElement = elementName
        currentElement = elementStack.last ?? ""
    }

    // Called when a CDATA block is found
    func parser(_ parser: XMLParser,
                foundCDATA CDATABlock: Data) {
        guard String(data: CDATABlock, encoding: .utf8) != nil else {
            print("CDATA contains non-textual data, ignored")
            return
        }
    }
}
