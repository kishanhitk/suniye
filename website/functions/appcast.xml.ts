import { handleAppcastRequest } from "../src/lib/appcast";

interface PagesFunctionContext {
  request: Request;
}

export async function onRequest({ request }: PagesFunctionContext): Promise<Response> {
  return handleAppcastRequest(request);
}
