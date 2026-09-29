// Notes CRUD handlers - identical code deployed to every region.
// AWS SDK v3 is bundled with the nodejs20.x runtime, so no node_modules needed.
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import {
  DynamoDBDocumentClient,
  GetCommand,
  PutCommand,
  UpdateCommand,
  DeleteCommand,
} from "@aws-sdk/lib-dynamodb";
import { randomUUID } from "node:crypto";

// The client talks to the LOCAL replica of the global table (same name everywhere).
const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}));
const TABLE_NAME = process.env.TABLE_NAME;
const REGION = process.env.AWS_REGION; // injected by Lambda

const respond = (statusCode, body) => ({
  statusCode,
  headers: { "Content-Type": "application/json", "X-Served-By-Region": REGION },
  body: JSON.stringify(body),
});

const parseBody = (event) => {
  try {
    return event.body ? JSON.parse(event.body) : {};
  } catch {
    return null;
  }
};

export const createNote = async (event) => {
  const data = parseBody(event);
  if (!data || !data.title) return respond(400, { message: "Body must be JSON with a 'title'." });

  const now = new Date().toISOString();
  const item = {
    id: randomUUID(),
    title: data.title,
    content: data.content ?? "",
    region: REGION, // which region accepted the write (same idea as the demo)
    createdAt: now,
    updatedAt: now,
  };

  await ddb.send(new PutCommand({ TableName: TABLE_NAME, Item: item }));
  return respond(201, item);
};

export const getNote = async (event) => {
  const id = event.pathParameters?.id;
  const { Item } = await ddb.send(new GetCommand({ TableName: TABLE_NAME, Key: { id } }));
  // Eventual consistency across regions: a note written in the other region
  // a few hundred ms ago may legitimately not be here yet.
  return Item ? respond(200, { ...Item, readFromRegion: REGION }) : respond(404, { message: "Note not found" });
};

export const updateNote = async (event) => {
  const id = event.pathParameters?.id;
  const data = parseBody(event);
  if (!data) return respond(400, { message: "Body must be valid JSON." });

  try {
    const { Attributes } = await ddb.send(
      new UpdateCommand({
        TableName: TABLE_NAME,
        Key: { id },
        UpdateExpression: "SET title = :t, content = :c, updatedAt = :u, updatedInRegion = :r",
        ConditionExpression: "attribute_exists(id)",
        ExpressionAttributeValues: {
          ":t": data.title ?? "",
          ":c": data.content ?? "",
          ":u": new Date().toISOString(),
          ":r": REGION,
        },
        ReturnValues: "ALL_NEW",
      })
    );
    return respond(200, Attributes);
  } catch (err) {
    if (err.name === "ConditionalCheckFailedException") return respond(404, { message: "Note not found" });
    throw err;
  }
};

export const deleteNote = async (event) => {
  const id = event.pathParameters?.id;
  await ddb.send(new DeleteCommand({ TableName: TABLE_NAME, Key: { id } }));
  return respond(204, {});
};

// Used by the Route 53 health check. It touches the local replica, so the
// region is reported unhealthy if Lambda OR the regional DynamoDB is broken.
export const health = async () => {
  try {
    await ddb.send(new GetCommand({ TableName: TABLE_NAME, Key: { id: "__healthcheck__" } }));
    return respond(200, { status: "ok", region: REGION });
  } catch (err) {
    console.error("health check failed", err);
    return respond(503, { status: "unhealthy", region: REGION });
  }
};
