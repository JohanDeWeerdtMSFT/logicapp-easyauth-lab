using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

var host = new HostBuilder()
    .ConfigureFunctionsWorkerDefaults()
    .ConfigureServices(services =>
    {
        // Application Insights telemetry for monitoring and evidence collection
        services.AddApplicationInsightsTelemetryWorkerService();
        services.ConfigureFunctionsApplicationInsights();

        // Register named HttpClient — avoids socket exhaustion from creating new HttpClient per call
        services.AddHttpClient("LogicAppClient");
    })
    .Build();

host.Run();
