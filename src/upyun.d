module upyun.d;

private import std.datetime;
private import std.format;
private import std.digest.md;
private import vibe.http.client;
private import vibe.stream.operations;

enum UpYunEndpoint {
   auto_ = 0,
   telecom,
   cnc,
   ctt
}

enum UpYunRet {
    ok = 0,
    invalidParams,
    notInited,
    fail,
    urlTooLong,
    invalidUrl,
    httpFail,
}

struct UpYunConfig {
    string user;
    string passwd;
    bool useHttps = false;
    bool debugOutput = false;
    UpYunEndpoint endpoint;
};

class UpYun {
private:
    enum {
        MaxFileNameLen = 1024,
        MaxHeaderLen = 512,
        MaxFileTypeLen = 20,
    }
    static string[] api_url_ = [
        "v0.api.upyun.com",
        "v1.api.upyun.com",
        "v2.api.upyun.com",
        "v3.api.upyun.com"
    ];

    UpYunConfig config_;
    string passhash_;

public:
    this(ref UpYunConfig config) {
        config_ = config;
        passhash_ = toHexString!(LetterCase.lower, Order.increasing)(md5Of(config_.passwd)).dup;
    }

    UpYunRet makeDir(string folder, bool autoMake, ref int statusCode) {
        string url = (config_.useHttps ? "https://" : "http://") ~ api_url_[config_.endpoint] ~ folder;
        requestHTTP(url, (scope req) {
            req.method = HTTPMethod.POST;
            req.headers["folder"] = "true";
            req.headers["mkdir"] = autoMake ? "true" : "false";
            req.headers["Host"] = api_url_[config_.endpoint];
            generateAuthHeader(req, folder, []);
        }, (scope res) {
            statusCode = res.statusCode;
            if(statusCode == 200)
                res.bodyReader.readAllUTF8();
        });
        return UpYunRet.ok;
    }

private:
    void generateAuthHeader(HTTPClientRequest req, string path, ubyte[] data) {
        string dt = rfc1123Time();
        req.headers["Date"] = dt;
        req.headers["Authorization"] = "UpYun %s:%s".format(config_.user,
            toHexString!(LetterCase.lower, Order.increasing)(md5Of("%s&%s&%s&%s&%s".format(
            req.method, path, dt, data.length, passhash_))));
        if(data.length > 0)
            req.bodyWriter.write(data);
    }

    static string[] daysOfWeek = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
    static string[] monthsOfYear = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    string rfc1123Time() {
        auto dt = cast(DateTime)Clock.currTime(UTC());
        return format("%s, %02d %s %04d %02d:%02d:%02d GMT",
                daysOfWeek[dt.dayOfWeek],
                dt.day,
                monthsOfYear[dt.month - 1],
                dt.year,
                dt.hour,
                dt.minute,
                dt.second);
    }
}

public UpYun createUpYun(ref UpYunConfig config) {
    return new UpYun(config);
}
