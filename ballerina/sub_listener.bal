// Copyright (c) 2021, WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
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
import ballerina/log;

# Represents a Subscriber Service listener endpoint.
public class Listener {
    private http:Listener httpListener;
    private http:ListenerConfiguration listenerConfig;
    private SubscriberServiceConfiguration? serviceConfig;
    private string? callbackUrl;
    private int port;
    private HttpService? httpService;

    # Initiliazes `websub:Listener` instance.
    # ```ballerina
    # listener websub:Listener websubListenerEp = check new (9090);
    # ```
    #
    # + listenTo - Port number or a `http:Listener` instance
    # + config - Custom `websub:ListenerConfiguration` to be provided to underlying HTTP Listener
    # + return - The `websub:Listener` or an `websub:Error` if the initialization failed
    public isolated function init(int|http:Listener listenTo, *ListenerConfiguration config) returns Error? {
        if listenTo is int {
            http:Listener|error httpListener = new(listenTo, config);
            if httpListener is http:Listener {
                self.httpListener = httpListener;
            } else {
                return error Error("Listener initialization failed", httpListener);
            }
        } else {
            self.httpListener = listenTo;
        }
        self.listenerConfig = self.httpListener.getConfig();
        self.port = self.httpListener.getPort();
        self.httpService = ();
        self.serviceConfig = ();
        self.callbackUrl = ();
    }

    # Attaches the provided `websub:SubscriberService` to the `websub:Listener`.
    # ```ballerina
    # check websubListenerEp.attach('service, "/subscriber");
    # ```
    # 
    # + subscriberService - The `websub:SubscriberService` object to attach
    # + name - The path of the Service to be hosted
    # + return - An `websub:Error`, if an error occurred during the service attaching process or else `()`
    public isolated function attach(SubscriberService subscriberService, string[]|string? name = ()) returns Error? {
        if self.listenerConfig.secureSocket is () {
            log:printWarn("HTTPS is recommended but using HTTP");
        }

        SubscriberServiceConfiguration? configuration = retrieveSubscriberServiceAnnotations(subscriberService);
        if configuration is SubscriberServiceConfiguration {
            self.serviceConfig = configuration;
            string[]|string servicePath = retrieveServicePath(name);
            self.callbackUrl = retrieveCallbackUrl(
                        configuration?.callback, configuration.appendServiceUrl, 
                        servicePath, self.port, self.listenerConfig);
            if isLoggingGeneratedCallback(configuration?.callback, name) {
                log:printInfo("Autogenerated callback ", URL = self.callbackUrl);
            }
            HttpToWebsubAdaptor adaptor = new (subscriberService);
            self.httpService = new (adaptor, configuration?.secret);
            error? result = self.httpListener.attach(<HttpService> self.httpService, servicePath);
            if (result is error) {
                return error Error("Error occurred while attaching the service", result);
            }
        } else {
            return error ListenerError("Could not find the required service-configurations");
        }
    }

    # Attaches the provided Service to the `websub:Listener` with custom `websub:SubscriberServiceConfiguration`.
    # ```ballerina
    # check websubListenerEp.attachWithConfig('service, {
    #    target: "http://0.0.0.0:9191/common/discovery",
    #    leaseSeconds: 36000
    # }, "/subscriber");
    # ```
    # 
    # + subscriberService - The `websub:SubscriberService` object to attach
    # + configuration - Custom `websub:SubscriberServiceConfiguration` which should be incorporated into the provided Service 
    # + name - The path of the Service to be hosted
    # + return - An `websub:Error`, if an error occurred during the service attaching process or else `()`
    public isolated function attachWithConfig(SubscriberService subscriberService, SubscriberServiceConfiguration configuration, string[]|string? name = ()) returns Error? {
        if self.listenerConfig.secureSocket is () {
            log:printWarn("HTTPS is recommended but using HTTP");
        }
        
        self.serviceConfig = configuration;
        string[]|string servicePath = retrieveServicePath(name);
        self.callbackUrl = retrieveCallbackUrl(
                        configuration?.callback, configuration.appendServiceUrl, 
                        servicePath, self.port, self.listenerConfig);
        if isLoggingGeneratedCallback(configuration?.callback, name) {
            log:printInfo("Autogenerated callback ", URL = self.callbackUrl);
        }
        HttpToWebsubAdaptor adaptor = new (subscriberService);
        self.httpService = new (adaptor, configuration?.secret);
        error? result = self.httpListener.attach(<HttpService> self.httpService, servicePath);
        if (result is error) {
            return error Error("Error occurred while attaching the service", result);
        }       
            
    }
    
    # Detaches the provided `websub:SubscriberService` from the `websub:Listener`.
    # ```ballerina
    # check websubListenerEp.detach('service);
    # ```
    # 
    # + s - The `websub:SubscriberService` object to be detached
    # + return - An `websub:Error`, if an error occurred during the service detaching process or else `()`
    public isolated function detach(SubscriberService s) returns Error? {
        error? result = self.httpListener.detach(<HttpService> self.httpService);
        if (result is error) {
            return error Error("Error occurred while detaching the service", result);
        }
    }

    # Starts the registered service programmatically..
    # ```ballerina
    # check websubListenerEp.'start();
    # ```
    # 
    # + return - An `websub:Error`, if an error occurred during the listener starting process or else `()`
    public isolated function 'start() returns Error? {
        error? listenerError = self.httpListener.'start();
        if (listenerError is error) {
            return error Error("Error occurred while starting the service", listenerError);
        }

        var serviceConfig = self.serviceConfig;
        var callback = self.callbackUrl;
        if serviceConfig is SubscriberServiceConfiguration {
            error? result = initiateSubscription(serviceConfig, <string>callback);
            if result is error {
                string errorDetails = result.message();
                string errorMsg = string `Subscription initiation failed due to: ${errorDetails}`;
                return error SubscriptionInitiationError(errorMsg);
            }
        }
    }

    # Stops the service listener gracefully. Already-accepted requests will be served before connection closure.
    # ```ballerina
    # check websubListenerEp.gracefulStop();
    # ```
    # 
    # + return - An `websub:Error`, if an error occurred during the listener stopping process or else `()`
    public isolated function gracefulStop() returns Error? {
        error? result = self.httpListener.gracefulStop();
        if (result is error) {
            return error Error("Error occurred while stopping the service", result);
        }
    }

    # Stops the service listener immediately.
    # ```ballerina
    # check websubListenerEp.immediateStop();
    # ```
    # 
    # + return - An `websub:Error`, if an error occurred during the listener stopping process or else `()`
    public isolated function immediateStop() returns Error? {
        error? result = self.httpListener.immediateStop();
        if (result is error) {
            return error Error("Error occurred while stopping the service", result);
        }
    }
}

# Retrieves the `websub:SubscriberServiceConfig` annotation values
# ```ballerina
# websub:SubscriberServiceConfiguration? config = retrieveSubscriberServiceAnnotations('service);
# ```
# 
# + serviceType - Current `websub:SubscriberService` object
# + return - Provided `websub:SubscriberServiceConfiguration` or else `()`
isolated function retrieveSubscriberServiceAnnotations(SubscriberService serviceType) returns SubscriberServiceConfiguration? {
    typedesc<any> serviceTypedesc = typeof serviceType;
    return serviceTypedesc.@SubscriberServiceConfig;
}

# Retrieves the service-path for the HTTP Service.
# ```ballerina
# string[]|string servicePath = retrieveServicePath("/subscriber");
# ```
# 
# + name - User provided service path
# + return - Value for the service path as `string[]` or `string`
isolated function retrieveServicePath(string[]|string? name) returns string[]|string {
    if name is () {
        return generateUniqueUrlSegment();
    } else if name is string {
        return name;
    } else {
        if (<string[]>name).length() == 0 {
            return generateUniqueUrlSegment();
        } else {
            return <string[]>name;
        }
    }
}

# Generates a unique URL segment for the HTTP Service.
# ```ballerina
# string urlSegment = generateUniqueUrlSegment();
# ```
# 
# + return - Generated service path
isolated function generateUniqueUrlSegment() returns string {
    string|error generatedString = generateRandomString(10);
    if generatedString is string {
        return generatedString;
    } else {
        return COMMON_SERVICE_PATH;
    }
}

# Retrieves callback URL which should be provided in subscription request.
# ```ballerina
# string callback = retrieveCallbackUrl("https://callback.com", true, "/subscriber", 9090, {});
# ```
# 
# + providedCallback - Optional user provided callback URL
# + appendServicePath - Flag representing whether to append service path to callback URL
# + servicePath - Current service path
# + port - Listener port for underlying `http:Listener`
# + config - Provided `http:ListenerConfiguration` for underlying `http:Listener`
# + return - Callback URL which should be used in subscription request
isolated function retrieveCallbackUrl(string? providedCallback, boolean appendServicePath, 
                                      string[]|string servicePath, int port, 
                                      http:ListenerConfiguration config) returns string {
    if providedCallback is string {
        if appendServicePath {
            string completeSevicePath = retrieveCompleteServicePath(servicePath);
            return string `${providedCallback}${completeSevicePath}`;
        } else {
            return providedCallback;
        }
    } else {
        return generateCallbackUrl(servicePath, port, config);
    }
}

# Dynamically generates the callback URL which should be provided in subscription request.
# ```ballerina
# string generatedCallback = generateCallbackUrl("/subscriber", 9090, {});
# ```
# 
# + servicePath - Current service path
# + port - Listener port for underlying `http:Listener`
# + config - Provided `http:ListenerConfiguration` for underlying `http:Listener`
# + return - Generated callback URL
isolated function generateCallbackUrl(string[]|string servicePath, 
                                     int port, http:ListenerConfiguration config) returns string {
    string host = config.host;
    string protocol = config.secureSocket is () ? "http" : "https";        
    string completeSevicePath = retrieveCompleteServicePath(servicePath);
    return string `${protocol}://${host}:${port.toString()}${completeSevicePath}`;
}

# Retrieves the complete service path.
# ```ballerina
# string completeServicePath = retrieveCompleteServicePath(["subscriber", "hub1"]);
# ```
# 
# + servicePath - User provided service path
# + return - Concatenated complete service path
isolated function retrieveCompleteServicePath(string[]|string servicePath) returns string {
    string concatenatedServicePath = "";
    if servicePath is string {
        concatenatedServicePath += "/" + <string>servicePath;
    } else {
        foreach var pathSegment in <string[]>servicePath {
            concatenatedServicePath += "/" + pathSegment;
        }
    }
    return concatenatedServicePath;
}

# Identifies whether or not to log callback URL.
# ```ballerina
# boolean shouldLogCallback = isLoggingGeneratedCallback("https://callback.com", ["subscriber", "hub1"]);
# ```
# 
# + providedCallback - Optional user provided callback URL
# + servicePath - user provided service path
# + return - 'true' if the user provided callback is `()` and service path is `()` or else 'false'
isolated function isLoggingGeneratedCallback(string? providedCallback, string[]|string? servicePath) returns boolean {
    return providedCallback is () && (servicePath is () || (servicePath is string[] && (<string[]>servicePath).length() == 0));
}

# Initiates the subscription to the `topic` in the mentioned `hub`.
# ```ballerina
# check initiateSubscription(serviceConfig, "https://callback.url/subscriber");
# ```
# 
# + serviceConfig - User provided `websub:SubscriberServiceConfiguration`
# + callbackUrl - Subscriber callback URL
# + return - An `error`, if an error occurred during the subscription-initiation or else `()`
isolated function initiateSubscription(SubscriberServiceConfiguration serviceConfig, string callbackUrl) returns error? {
    string|[string, string]? target = serviceConfig?.target;
        
    string hubUrl;
    string topicUrl;
        
    if target is string {
        var discoveryConfig = serviceConfig?.discoveryConfig;
        http:ClientConfiguration? discoveryHttpConfig = discoveryConfig?.httpConfig ?: ();
        string?|string[] expectedMediaTypes = discoveryConfig?.accept ?: ();
        string?|string[] expectedLanguageTypes = discoveryConfig?.acceptLanguage ?: ();

        DiscoveryService discoveryClient = check new (target, discoveryConfig?.httpConfig);
        var discoveryDetails = discoveryClient->discoverResourceUrls(expectedMediaTypes, expectedLanguageTypes);
        if discoveryDetails is [string, string] {
            [hubUrl, topicUrl] = <[string, string]> discoveryDetails;
        } else {
            return error ResourceDiscoveryFailedError(discoveryDetails.message());
        }
    } else if target is [string, string] {
        [hubUrl, topicUrl] = <[string, string]> target;
    } else {
        log:printWarn("Subscription not initiated as subscriber target-URL is not provided");
        return;
    }

    SubscriptionClient subscriberClientEp = check getSubscriberClient(hubUrl, serviceConfig?.httpConfig);
    SubscriptionChangeRequest request = retrieveSubscriptionRequest(topicUrl, callbackUrl, serviceConfig);
    var response = subscriberClientEp->subscribe(request);
    if response is SubscriptionChangeResponse {
        string subscriptionSuccessMsg = string `Subscription Request successfully sent to Hub[${response.hub}], for Topic[${response.topic}], with Callback [${callbackUrl}]`;
        log:printDebug(subscriptionSuccessMsg);
    } else {
        return response;
    }
}

# Initializes a subscriber-client with provided configurations.
# ```ballerina
# websub:SubscriptionClient subscriptionClientEp = check getSubscriberClient("https://sample.hub.com", clientConfig);
# ```
# 
# + hubUrl - URL of the hub to which subscriber is going to subscribe
# + config - Optional `http:ClientConfiguration` to be provided to underlying `http:Client`
# + return - Initilized `websub:SubscriptionClient` or else `error`
isolated function getSubscriberClient(string hubUrl, http:ClientConfiguration? config) returns SubscriptionClient|error {
    if config is http:ClientConfiguration {
        return check new SubscriptionClient(hubUrl, config); 
    } else {
        return check new SubscriptionClient(hubUrl);
    }
}