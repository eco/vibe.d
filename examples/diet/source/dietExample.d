import vibe.d;

void handleRequest(HttpServerRequest req, HttpServerResponse res)
{
	string local_var = "Hello, World!";
	res.headers["Content-Type"] = "text/html";
	
	auto output = res.bodyWriter();
	//parseDietFile!("diet.dt", req, local_var)(output);
	res.renderCompat!("diet.dt",
		HttpServerRequest, "req",
		string, "local_var")(req, local_var);
}

shared static this()
{
	auto settings = new HttpServerSettings;
	settings.port = 8080;
	
	listenHttp(settings, &handleRequest);
}
