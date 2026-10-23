import Foundation
import JavaScriptCore

struct CatalogFilter: Codable, Hashable {
    var source="all"
    var type="all"
    var status="all"
    var genres: [String] = []
    var requiresMetadata: Bool { type != "all" || status != "all" || !genres.isEmpty }
}
struct StorySourceGroup: Codable, Identifiable {
    let id: String
    let primary: Story
    let items: [Story]
}
struct CatalogOption: Decodable, Identifiable { let id: String; let label: String }
struct CatalogOptions: Decodable {
    let genres: [CatalogOption]
    let types: [CatalogOption]
    let statuses: [CatalogOption]
}
enum CatalogRules {
    static let options: CatalogOptions = {
        guard let url=Bundle.main.url(forResource:"DiscoveryOptions",withExtension:"json"),let data=try? Data(contentsOf:url),let value=try? JSONDecoder().decode(CatalogOptions.self,from:data) else { return CatalogOptions(genres:[],types:[],statuses:[]) }
        return value
    }()
    static func groups(_ stories: [Story],filter: CatalogFilter = CatalogFilter()) async -> [StorySourceGroup] {
        let result=await Task.detached(priority:.userInitiated) { () -> [StorySourceGroup]? in
            guard let url=Bundle.main.url(forResource:"FeedEngine",withExtension:"js"),let source=try? String(contentsOf:url),let context=JSContext() else { return nil }
            context.evaluateScript(source)
            guard context.exception == nil,
                  let input=try? JSONSerialization.jsonObject(with:JSONEncoder().encode(stories)),
                  let filter=try? JSONSerialization.jsonObject(with:JSONEncoder().encode(filter)),
                  let output=context.objectForKeyedSubscript("catalogGroups").call(withArguments:[input,filter]),
                  let object=output.toArray(),JSONSerialization.isValidJSONObject(object),
                  let data=try? JSONSerialization.data(withJSONObject:object),
                  let groups=try? JSONDecoder().decode([StorySourceGroup].self,from:data) else { return nil }
            return groups
        }.value
        return result ?? stories.map { StorySourceGroup(id:$0.key,primary:$0,items:[$0]) }
    }
}
