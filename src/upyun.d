module upyun.d;

private import std.algorithm: startsWith;
private import std.array: join;
private import std.datetime;
private import std.digest.md;
private import std.file: read, write, exists;
private import std.format: format;
private import std.string: split;
private import vibe.data.json;
private import vibe.http.client;
private import vibe.http.form;
private import vibe.stream.operations;

/// UpYun Endpoints
public enum UpYunEndpoint {
    /// Auto select
    auto_ = 0,
    /// China Telecom
    telecom,
    /// China Unicom(China Netcom)
    cnc,
    /// China Tietong(China Mobile)
    ctt
}

/// UpYun function return value
public struct UpYunRet {
    /// HTTP status code
    int statusCode;
    /// Error code
    int errorCode;
    /// Error message
    string errorMsg;
}

/// UpYun config
public struct UpYunConfig {
    /// Username
    string user;
    /// Password
    string passwd;
    /// Bucket path, begins with '/'
    string bucket;
    /// Using https:// instead of http://
    bool useHttps = false;
    // Print some debug information
    bool debugOutput = false;
    // Network endpoint
    UpYunEndpoint endpoint;
};

/// UpYun file info used in listDir
public struct UpYunFileInfo {
    /// File name
    string filename;
    /// Is folder or not
    bool isFolder;
    /// File size in bytes
    ulong size;
    /// Unix timestamp
    ulong timestamp;
}

/// UpYun main class
public class UpYun {
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
    static string purge_url_ = "http://purge.upyun.com/purge/";

    UpYunConfig config_;
    string passhash_;

    struct UpYunRetInternal {
        UpYunRet ret;
        string[string] response;
        ubyte[] bodyRaw;
    }

public:
    /// Create UpYun object with certain config
    this(ref UpYunConfig config) {
        config_ = config;
        passhash_ = toHexString!(LetterCase.lower, Order.increasing)(md5Of(config_.passwd)).dup;
    }

    /**
     * Upload a file
     *
     * Params:
     *   path        = remote path
     *   localFile   = local file path
     *   md5Verify   = emit md5 field to verify file after uploading finished
     *   contentType = overwrite auto detected 'Content-Type' for the file
     *   secret      = secret key for visiting
     */
    UpYunRet uploadFile(string path, string localFile, bool md5Verify = false, string contentType = null, string secret = null) {
        if(!exists(localFile)) {
            return UpYunRet(-1, -1, "File not found!");
        }
        return uploadFile(path, cast(ubyte[])read(localFile), md5Verify, contentType, secret);
    }

    /**
     * Upload a file
     *
     * Params:
     *   path        = remote path
     *   data        = file content
     *   md5Verify   = emit md5 field to verify file after uploading finished
     *   contentType = overwrite auto detected 'Content-Type' for the file
     *   secret      = secret key for visiting
     */
    UpYunRet uploadFile(string path, ubyte[] data, bool md5Verify = false, string contentType = null, string secret = null) {
        string[string] headers;
        if(md5Verify) headers["Content-MD5"] = toHexString!(LetterCase.lower, Order.increasing)(md5Of(data));
        if(contentType !is null) headers["Content-Type"] = contentType;
        if(secret !is null) headers["Content-Secret"] = secret;
        return requestInternal(path, HTTPMethod.PUT, headers, data).ret;
    }

    /**
     * Download a file
     *
     * Params:
     *   path        = remote path
     *   content     = file content downloaded
     */
    UpYunRet downloadFile(string path, ref ubyte[] content) {
        auto r = requestInternal(path, HTTPMethod.GET);
        if(r.ret.statusCode == 200)
            content = r.bodyRaw;
        return r.ret;
    }

    /**
     * Download a file
     *
     * Params:
     *   path        = remote path
     *   localFile   = local path for the downloaded file
     */
    UpYunRet downloadFile(string path, string localFile) {
        ubyte[] content;
        auto ret = downloadFile(path, content);
        if(ret.statusCode == 200)
            write(localFile, content);
        return ret;
    }

    /**
     * Get information for a file
     *
     * Params:
     *   path        = remote path
     *   type        = receives 'Content-Type'
     *   size        = receives file size in bytes
     *   timestamp   = receives file time in unix timestamp
     */
    UpYunRet fileInfo(string path, ref string type, ref ulong size, ref ulong timestamp) {
        auto r = requestInternal(path, HTTPMethod.HEAD);
        if(r.ret.statusCode == 200) {
            auto p = "file-type" in r.response;
            if(p) type = *p;
            p = "file-size" in r.response;
            if(p) size = (*p).to!ulong;
            p = "file-date" in r.response;
            if(p) timestamp = (*p).to!ulong;
        }
        return r.ret;
    }

    /**
     * Delete a file
     *
     * Params:
     *   path        = remote file path to delete
     */
    UpYunRet deleteFile(string path) {
        return requestInternal(path, HTTPMethod.DELETE).ret;
    }

    /**
     * Create a directory
     *
     * Params:
     *   path        = remote directory path to create
     *   autoMake    = make directories recursively
     */
    UpYunRet makeDir(string path, bool autoMake = false) {
        return requestInternal(path, HTTPMethod.POST, ["folder": "true", "mkdir": autoMake ? "true" : "false"]).ret;
    }

    /**
     * List files in a directory
     *
     * Params:
     *   path        = remote directory path to list
     *   files       = receive files' information
     */
    UpYunRet listDir(string path, ref UpYunFileInfo[] files) {
        auto r = requestInternal(path, HTTPMethod.GET);
        if(r.ret.statusCode == 200) {
            auto content = cast(string)r.bodyRaw;
            foreach(l; content.split('\n')) {
                auto fields = l.split('\t');
                if(fields.length >= 4) {
                    files ~= UpYunFileInfo(fields[0], fields[1] == "F", fields[2].to!ulong, fields[3].to!ulong);
                }
            }
        }
        return r.ret;
    }

    /**
     * Get bucket space usage
     *
     * Params:
     *   path        = remote directory path
     *   bytes       = receive bytes used
     */
    UpYunRet getUsage(string path, ref ulong bytes) {
        auto r = requestInternal(path ~ ((path.length == 0 || path[$-1] != '/') ? "/?usage" : "?usage"), HTTPMethod.GET);
        if(r.ret.statusCode == 200)
            bytes = (cast(string)r.bodyRaw).to!ulong;
        return r.ret;
    }

    /**
     * Purge CDN caches
     *
     * Params:
     *   urls        = list of urls, please supply COMPLETE http urls
     */
    int purge(string[] urls) {
        int statusCode = -1;
        string purl = urls.join('\n');
        requestHTTP(purge_url_, (scope req) {
            req.method = HTTPMethod.POST;
            string dt = rfc1123Time();
            req.headers["Date"] = dt;
            req.headers["Authorization"] = "UpYun %s:%s:%s".format(config_.bucket, config_.user,
                toHexString!(LetterCase.lower, Order.increasing)(md5Of("%s&%s&%s&%s".format(
                purl, config_.bucket, dt, passhash_))));
            req.writeFormBody(["purge": purl]);
        }, (scope res) {
            statusCode = res.statusCode;
            std.stdio.writefln("%s", res.bodyReader.readAllUTF8());
        });
        return statusCode;
    }

private:
    UpYunRetInternal requestInternal(string path, HTTPMethod method, const string[string] headers = null, ubyte[] data = []) {
        UpYunRetInternal result;
        string basepath = "/" ~ config_.bucket ~ path;
        string url = (config_.useHttps ? "https://" : "http://") ~ api_url_[config_.endpoint] ~ basepath;
        requestHTTP(url, (scope req) {
            req.method = method;
            string dt = rfc1123Time();
            req.headers["Host"] = api_url_[config_.endpoint];
            req.headers["Date"] = dt;
            req.headers["Authorization"] = "UpYun %s:%s".format(config_.user,
                toHexString!(LetterCase.lower, Order.increasing)(md5Of("%s&%s&%s&%s&%s".format(
                method, basepath, dt, data.length, passhash_))));
            foreach(ref k, ref v; headers) {
                req.headers[k] = v;
            }
            if(data.length > 0)
                req.bodyWriter.write(data);
        }, (scope res) {
            result.ret.statusCode = res.statusCode;
            if(result.ret.statusCode != 200) {
                try {
                    auto j = res.readJson();
                    auto code = j.code;
                    if(code.type == Json.Type.int_)
                        result.ret.errorCode = code.to!int;
                    auto msg = j.msg;
                    if(msg.type == Json.Type.string)
                        result.ret.errorMsg = msg.to!string;
                } catch { }
            } else {
                try {
                    result.bodyRaw = res.bodyReader.readAll();
                } catch {}
            }
            foreach(k, v; res.headers) {
                if(k.startsWith("x-upyun-"))
                    result.response[k[8..$]] = v;
            }
        });
        return result;
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
