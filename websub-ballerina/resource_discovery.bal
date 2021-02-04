// Copyright (c) 2021 WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
//
// WSO2 Inc. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/http;
import ballerina/lang.'string as strings;
import ballerina/regex;

public client class DiscoveryService {
    private string resourceUrl;
    private http:Client discoveryClientEp;

    public function init(string discoveryUrl, 
                         http:ClientConfiguration? publisherClientConfig) returns error? {
        self.resourceUrl = discoveryUrl;
        self.discoveryClientEp = check new (discoveryUrl, publisherClientConfig);
    }

    # Discovers the hub and topic URLs defined by a resource URL.
    #
    # + expectedMediaTypes - The expected media types for the subscriber client
    # + expectedLanguageTypes - The expected language types for the subscriber client
    # + return - A `(hub, topic)` as a `(string, string)` if successful or else an `error` if not
    remote function discoverResourceUrls(string?|string[] expectedMediaTypes, string?|string[] expectedLanguageTypes) 
                                        returns @tainted [string, string]|error {
        http:Request request = new;
    
        if (expectedMediaTypes is string) {
            request.addHeader(ACCEPT_HEADER, expectedMediaTypes);
        }
    
        if (expectedMediaTypes is string[]) {
            string acceptMeadiaTypesString = expectedMediaTypes[0];
            foreach int expectedMediaTypeIndex in 1 ... (expectedMediaTypes.length() - 1) {
                acceptMeadiaTypesString = acceptMeadiaTypesString.concat(", ", expectedMediaTypes[expectedMediaTypeIndex]);
            }
            request.addHeader(ACCEPT_HEADER, acceptMeadiaTypesString);
        }
    
        if (expectedLanguageTypes is string) {
            request.addHeader(ACCEPT_LANGUAGE_HEADER, expectedLanguageTypes);
        }
    
        if (expectedLanguageTypes is string[]) {
            string acceptLanguageTypesString = expectedLanguageTypes[0];
            foreach int expectedLanguageTypeIndex in 1 ... (expectedLanguageTypes.length() - 1) {
                acceptLanguageTypesString = acceptLanguageTypesString.concat(", ", expectedLanguageTypes[expectedLanguageTypeIndex]);
            }
            request.addHeader(ACCEPT_LANGUAGE_HEADER, acceptLanguageTypesString);
        }

        var discoveryResponse = self.discoveryClientEp->get("", request);

        if (discoveryResponse is http:Response) {
            var topicAndHubs = extractTopicAndHubUrls(discoveryResponse);
            if (topicAndHubs is [string, string[]]) {
                string topic = "";
                string[] hubs = [];
                [topic, hubs] = topicAndHubs;
                return [hubs[0], topic]; // guaranteed by `extractTopicAndHubUrls` for hubs to have length > 0
            } else {
                return topicAndHubs;
            }
        } else {
            return error Error("Error occurred with WebSub discovery for Resource URL [" + self.resourceUrl + "]: " +
                            (<error>discoveryResponse).message());
        }                                       
    }
}

# Retrieves hub and topic URLs from the `http:response` from a publisher to a discovery request.
#
# + response - An `http:Response` received
# + return - A `(topic, hubs)` if parsing and extraction is successful or else an `error` if not
function extractTopicAndHubUrls(http:Response response) returns @tainted [string, string[]]|error {
    string[] linkHeaders = [];
    if (response.hasHeader("Link")) {
        linkHeaders = check response.getHeaders("Link");
    }
    
    if (response.statusCode == http:STATUS_NOT_ACCEPTABLE) {
        return error Error("Content negotiation failed.Accept and/or Accept-Language headers mismatch");
    }
    
    if (linkHeaders.length() == 0) {
        return error Error("Link header unavailable in discovery response");
    }

    int hubIndex = 0;
    string[] hubs = [];
    string topic = "";
    string[] linkHeaderConstituents = [];
    if (linkHeaders.length() == 1) {
        linkHeaderConstituents = regex:split(linkHeaders[0], ",");
    } else {
        linkHeaderConstituents = linkHeaders;
    }

    foreach var link in linkHeaderConstituents {
        string[] linkConstituents = regex:split(link, ";");
        if (linkConstituents[1] != "") {
            string url = linkConstituents[0].trim();
            url = regex:replaceAll(url, "<", "");
            url = regex:replaceAll(url, ">", "");
            if (strings:includes(linkConstituents[1], "rel=\"hub\"")) {
                hubs[hubIndex] = url;
                hubIndex += 1;
            } else if (strings:includes(linkConstituents[1], "rel=\"self\"")) {
                if (topic != "") {
                    return error Error("Link Header contains > 1 self URLs");
                } else {
                    topic = url;
                }
            }
        }
    }

    if (hubs.length() > 0 && topic != "") {
        return [topic, hubs];
    }
    return error Error("Hub and/or Topic URL(s) not identified in link header of discovery response");
}