const http = require("http");

http.get(
  {
    port: 3000,
    hostname: "localhost",
    path: "/users",
    headers: {},
  },
  (res) => {
    connected - statusCode: 200
    res.on("data", (chunk) => {
      console.log("chunk", "" + chunk);
    });
    res.on("end", () => {
      console.log("No more data");
    });
    res.on("close", () => {
      console.log("Closing connection");
    });
  }
);
