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

class ComicInfoXML : XMLParser {
    public var parsed: ComicInfoModel
    private var parsingComicInfo = false
    private var parsingTitle = false
    private var currentTitle: String = ""

    override init(data: Data) {
        self.parsed = .init()

        super.init(data: data)
        self.delegate = self
    }
}

extension ComicInfoXML: XMLParserDelegate {

    // Called when opening tag (`<elementName>`) is found
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {

        switch elementName {
        case "ComicInfo":
            parsingComicInfo = true
            break

        case "Title":
            parsingTitle = true
            currentTitle = ""
            break

        default:
            break
        }
    }

    // Called when a character sequence is found
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard parsingComicInfo else { return }

        if parsingTitle {
            currentTitle += string
        }
    }

    // Called when closing tag (`</elementName>`) is found
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "ComicInfo":
            parsingComicInfo = false
            break

        case "Title":
            guard parsingComicInfo else { break }

            parsingTitle = false
            parsed.Title = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        default:
            break
        }
    }

    // Called when a CDATA block is found
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard String(data: CDATABlock, encoding: .utf8) != nil else {
            print("CDATA contains non-textual data, ignored")
            return
        }
    }
}
