import Foundation
import AWSCloudWatch
import Mockable
import Domain

// MARK: - CloudWatch Metric Data

/// Represents raw metric data from CloudWatch for a single model
public struct BedrockMetricData: Sendable, Equatable {
    public let modelId: String
    public let inputTokens: Int
    public let outputTokens: Int
    public let invocations: Int

    public init(modelId: String, inputTokens: Int, outputTokens: Int, invocations: Int) {
        self.modelId = modelId
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.invocations = invocations
    }
}

// MARK: - BedrockCloudWatchClient Protocol

/// Protocol for fetching Bedrock usage metrics from CloudWatch.
/// Abstracted for testability - production uses AWSCloudWatchClient.
@Mockable
public protocol BedrockCloudWatchClient: Sendable {
    /// Fetches Bedrock usage metrics for the specified time period
    /// - Parameters:
    ///   - region: AWS region to query
    ///   - startTime: Start of the time period
    ///   - endTime: End of the time period
    /// - Returns: Array of metric data per model
    func fetchBedrockMetrics(
        region: String,
        startTime: Date,
        endTime: Date
    ) async throws -> [BedrockMetricData]

    /// Verifies AWS credentials are valid
    /// - Returns: True if credentials can authenticate successfully
    func verifyCredentials() async -> Bool
}

// MARK: - Default Implementation

/// Production implementation using AWS SDK CloudWatch client
public final class AWSBedrockCloudWatchClient: BedrockCloudWatchClient, @unchecked Sendable {

    private let profileName: String?

    public init(profileName: String? = nil) {
        self.profileName = profileName
    }

    public func fetchBedrockMetrics(
        region: String,
        startTime: Date,
        endTime: Date
    ) async throws -> [BedrockMetricData] {
        // Build CloudWatch client for the specified region
        let client = try buildClient(region: region)

        // Get list of models by querying for Invocations metric with ModelId dimension
        let modelIds = try await listBedrockModels(client: client, startTime: startTime, endTime: endTime)

        // Fetch metrics for each model
        var results: [BedrockMetricData] = []
        for modelId in modelIds {
            let metrics = try await fetchMetricsForModel(
                client: client,
                modelId: modelId,
                startTime: startTime,
                endTime: endTime
            )
            results.append(metrics)
        }

        return results
    }

    public func verifyCredentials() async -> Bool {
        do {
            // Try to create a client and make a simple call
            let client = try buildClient(region: "us-east-1")
            // List metrics is a cheap call to verify credentials work
            let input = ListMetricsInput(namespace: "AWS/Bedrock")
            _ = try await client.listMetrics(input: input)
            return true
        } catch {
            AppLog.probes.warning("AWS credential verification failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Private Helpers

    private func buildClient(region: String) throws -> CloudWatchClient {
        // Configure client with profile if specified
        // AWS SDK will automatically read from ~/.aws/credentials
        try CloudWatchClient(region: region)
    }

    private func listBedrockModels(
        client: CloudWatchClient,
        startTime: Date,
        endTime: Date
    ) async throws -> [String] {
        // Query CloudWatch for all unique ModelId values in the time range
        let input = ListMetricsInput(
            dimensions: [
                CloudWatchClientTypes.DimensionFilter(name: "ModelId")
            ],
            namespace: "AWS/Bedrock",
            recentlyActive: .pt3h
        )

        var modelIds: Set<String> = []
        var nextToken: String? = nil

        repeat {
            var paginatedInput = input
            paginatedInput.nextToken = nextToken

            let output = try await client.listMetrics(input: paginatedInput)

            for metric in output.metrics ?? [] {
                if let dimensions = metric.dimensions {
                    for dimension in dimensions {
                        if dimension.name == "ModelId", let value = dimension.value {
                            modelIds.insert(value)
                        }
                    }
                }
            }

            nextToken = output.nextToken
        } while nextToken != nil

        return Array(modelIds)
    }

    private func fetchMetricsForModel(
        client: CloudWatchClient,
        modelId: String,
        startTime: Date,
        endTime: Date
    ) async throws -> BedrockMetricData {
        // Calculate period - we want a single data point for the entire range
        let periodSeconds = Int(endTime.timeIntervalSince(startTime))

        let modelDimension = CloudWatchClientTypes.Dimension(name: "ModelId", value: modelId)

        // Fetch metrics sequentially to avoid data race with non-Sendable client
        let inputTokens = try await fetchMetricSum(
            client: client,
            metricName: "InputTokenCount",
            dimensions: [modelDimension],
            startTime: startTime,
            endTime: endTime,
            period: periodSeconds
        )

        let outputTokens = try await fetchMetricSum(
            client: client,
            metricName: "OutputTokenCount",
            dimensions: [modelDimension],
            startTime: startTime,
            endTime: endTime,
            period: periodSeconds
        )

        let invocations = try await fetchMetricSum(
            client: client,
            metricName: "Invocations",
            dimensions: [modelDimension],
            startTime: startTime,
            endTime: endTime,
            period: periodSeconds
        )

        return BedrockMetricData(
            modelId: modelId,
            inputTokens: Int(inputTokens),
            outputTokens: Int(outputTokens),
            invocations: Int(invocations)
        )
    }

    private func fetchMetricSum(
        client: CloudWatchClient,
        metricName: String,
        dimensions: [CloudWatchClientTypes.Dimension],
        startTime: Date,
        endTime: Date,
        period: Int
    ) async throws -> Double {
        let input = GetMetricStatisticsInput(
            dimensions: dimensions,
            endTime: endTime,
            metricName: metricName,
            namespace: "AWS/Bedrock",
            period: period,
            startTime: startTime,
            statistics: [.sum]
        )

        let output = try await client.getMetricStatistics(input: input)

        // Sum up all datapoints (should be just one with our period setting)
        let total = output.datapoints?.reduce(0.0) { $0 + ($1.sum ?? 0) } ?? 0
        return total
    }
}
